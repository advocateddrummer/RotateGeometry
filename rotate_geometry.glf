# This script rotates geometry in a Pointwise project, re-initializes any block
# containing modified geometry, and exports the resulting mesh/CAE. The
# Pointwise project file _is not_ saved/modified.
#
# Author: Ethan Alan Hereth
# Email: ehereth@utk.edu or e.a.hereth@gmail.com

package require PWI_Glyph 3.18.3

puts "Running $argv0 with: [pw::Application getVersion]"

set help "Usage: The Pointwise project file must be passed to this script as
       the first argument and rotation angle(s) as the second. Multiple angles
       may be passed and if fewer angles are provided than required, the last
       angle will be reused. You may pass the --verify argument as well to have
       this script export the rotated boundaries only for initial verification.
       Lastly, the --verbose/-v flag may be passed to make this script more
       verbose."

if { $argc < 2 } {
  puts ""
  puts "################################################################################"
  puts $help
  puts "################################################################################"
  puts ""
  exit
} else {
  puts "Calling $argv0 with the following arguments: $argv"
  # Look for --verify in argument list
  set verify false
  set idx [lsearch $argv "--verify"]
  if { $idx != -1 } {
    puts "Running in verify mode"
    set verify true
    # Remove --verify argument from list
    set argv [lreplace $argv $idx $idx]
  }

  # Look for --verbose in argument list
  set verbose false
  set idx [lsearch $argv "--verbose"]
  # Also check for -v
  if { $idx == -1 } {
    set idx [lsearch $argv "-v"]
  }

  if { $idx != -1 } {
    puts "Running in verbose mode"
    set verbose true
    # Remove --verbose/-v argument from list
    set argv [lreplace $argv $idx $idx]
  }

  set pwFile [lindex $argv 0]
  if { [string match "*.pw" $pwFile] } {
    puts "Opening Pointwise project file $pwFile"
  } else {
    puts "ERROR: the first argument must be a Pointwise project file (ending in .pw)"
    exit
  }

  # The remaining arguments should be rotation angles for the geometry;
  # currently there is no error checking/verification. At least one angle must
  # be specified, however, multiple may be specified, and if less than then the
  # appropriate number of angles are specified, the last one is reused.
  set rotateAngles [lrange $argv 1 end]
  puts "Rotating model(s) by $rotateAngles degrees"
}

# Set current working directory to be used as the base for saving files
set currentDirectory [pwd]

if { $verbose == true } { puts "loading $pwFile..." }
pw::Application reset
pw::Application load "$pwFile"
if { $verbose == true } { puts "loaded $pwFile..." }

pw::Application setUndoMaximumLevels 20

# Get a list of all models in the project
set models [pw::Database getAll -type pw::Model]

# Initialize empty list for the models to be rotated; this list contains both
# the internal model name as well as the user given name (rotate-*) as a sort
# of key pair.
set rotateModelList [list]

# Look for any model(s) named like rotate-* (rotate-1, rotate-2, etc.)
foreach m $models {
  set name [$m getName]
  if { [string match "rotate-*" $name] } {
    lappend rotateModelList [list $name $m]
  }
}

if { [llength $rotateModelList] == 0 } {
  puts "ERROR: there must be at least one model named rotate-*"
  exit
} else {
  puts "Found [llength $rotateModelList] [expr { [llength $rotateModelList] > 1 ? "models" : "model" }] to rotate"
}

# Sort the rotateModelList by its first sub-list item, the user assigned name.
set rotateModelList [lsort -index 0 $rotateModelList]

if { $verbose == true } {
  puts ""
  puts "Rotate model list: $rotateModelList"
  puts ""
}

# Create file name template; I do not like this name string, but it should be
# clear albeit ugly
set angleIndex 0
set fileName [lindex  [split $pwFile .] 0]
foreach i $rotateModelList {
  set name [lindex $i 0]
  set rotateAngle [expr {$angleIndex >= [llength $rotateAngles] ? [lindex $rotateAngles end] : [lindex $rotateAngles $angleIndex]}]
  lappend fileName $name $rotateAngle
  incr angleIndex
}

set fileName [join $fileName _]

# Now look for rotation axis information which should be at least two points
# named rotate-*-point-1 and rotate-*-point-2, two for each model to be
# rotated.
set points [pw::Database getAll -type pw::Point]
# Initialize empty lists for the model rotation points
set rotatePoints [list]
set rotatePointNames [list]

# Look for points named like rotate-*-point-1 and rotate-*-point-2
# (rotate-1-point-1, rotate-1-point-2, etc.), one pair for each model to
# rotate.
# Note: this logic extracts the rotation points in the proper order, as defined
# by the user, so that the rotation direction is proper. The way this was done
# before did not necessarily create the proper rotation axes.
set modelIndex 1
foreach m $rotateModelList {
  set ptName1 "rotate-$modelIndex-point-1"
  set ptName2 "rotate-$modelIndex-point-2"
  set pt1 [pw::DatabaseEntity getByName $ptName1]
  set pt2 [pw::DatabaseEntity getByName $ptName2]
  # TODO: check for existence of these points; do not assume they were found.
  lappend rotatePoints $pt1 $pt2
  lappend rotatePointNames $ptName1 $ptName2
  incr modelIndex
}

if { [llength $rotatePoints] == 0 } {
  puts "ERROR: there must be one pair of points named rotate-*-point-1, rotate-*-point-2 for each model to be rotated"
  exit
} elseif { [expr {[llength $rotatePoints] % 2 }] != 0 } {
  puts "ERROR: there must be an even number of points to define a rotation axis"
  exit
} else {
  puts "Found [llength $rotatePoints] points to define [expr { [llength $rotatePoints] > 2 ? "rotation axes" : "a rotation axis" } ]"
}

if { $verbose == true } {
  puts ""
  puts "Rotate points: $rotatePoints"
  puts "Rotate point names: $rotatePointNames"
  puts ""
}

# Build up list of internal model names for the Modify mode below
set rotateModels [list]
foreach i $rotateModelList {
  set m [lindex $i 1]
  lappend rotateModels $m
}

set rotateMode [pw::Application begin Modify $rotateModels]

  set pointIndex 0
  set angleIndex 0
  foreach pair $rotateModelList {
    # Get internal model name
    set model [lindex $pair 0]
    set modelName [lindex $pair 1]

    # Get axis point coordinates
    set pt1 [lindex $rotatePoints $pointIndex]
    set pt1Coord [$pt1 getXYZ]
    incr pointIndex
    set pt2 [lindex $rotatePoints $pointIndex]
    set pt2Coord [$pt2 getXYZ]
    incr pointIndex

    #puts "Rotating model $m (named [$m getName]) about the points:\
          $pt2 and $pt2 (named [$pt1 getName] at $pt1Coord and [$pt2 getName] at $pt2Coord)"
    if { $verbose == true } {
      puts ""
      puts "Rotating model $model (named $modelName) about the points:\
            $pt2 and $pt2 (named [$pt1 getName] at $pt1Coord and [$pt2 getName] at $pt2Coord)"
      puts ""
    }

    # Define rotation axis
    set rotateAxis [pwu::Vector3 normalize [pwu::Vector3 subtract $pt1Coord $pt2Coord]]
    set rotateAnchor $pt1Coord

    set rotateAngle [expr {$angleIndex >= [llength $rotateAngles] ? [lindex $rotateAngles end] : [lindex $rotateAngles $angleIndex]}]
    incr angleIndex
    if { $verbose == true } { puts "The rotation angle is $rotateAngle degrees about axis: $rotateAxis" }

    # Perform rotation
    pw::Entity transform [pwu::Transform rotation -anchor $rotateAnchor $rotateAxis $rotateAngle] $modelName
  }

$rotateMode end
unset rotateMode
pw::Application markUndoLevel Rotate

set rotateBlock [pw::GridEntity getByName rotate-block-1]

if { $verify } {
  puts "Not initializing block in verify mode"
  # Get block faces
  set rotateBlockFaces [$rotateBlock getFaces]
  # Extract domains from faces
  set rotateBlockDomains [list]
  foreach f $rotateBlockFaces {
    set domains [$f getDomains]
    # Convoluted way to make sure this is a flat list a la: https://stackoverflow.com/a/17636938
    set rotateBlockDomains [list {*}$rotateBlockDomains {*}$domains]
  }
  #puts "rotateBlockFaces: $rotateBlockFaces"
  #puts "rotateBlockDomains: $rotateBlockDomains"
  #puts "rotateBlockDomains sorted: [pw::Entity sort $rotateBlockDomains]"

  set gridExporter [pw::Application begin GridExport [pw::Entity sort $rotateBlockDomains]]
    set status abort
    # This does not work as Pointwise's Glyph page claims it should:
    #if { $gridExporter && [$gridExporter initialize -strict -type grid /Users/ehereth/Downloads/foobar.cgns] }
    if { [$gridExporter initialize -strict -type CGNS "$currentDirectory/$fileName-boundaries.cgns"] } {
      puts "gridExporter initialize succeeded..."
      if { [$gridExporter verify] && [$gridExporter canWrite] && [$gridExporter write] } {
        puts "gridExporter {verify,canWrite,write} succeeded..."
        set status end
      } else { puts "gridExporter {verify,canWrite,write} failed..." }
    }

  $gridExporter $status
  unset gridExporter
  puts "####################################################################################################"
  puts "Exported the rotated boundaries to $currentDirectory/$fileName-boundaries.cgns"
  puts "\tcheck this for validity and then re-run this script without the \"--verify\" flag"
  puts "####################################################################################################"
} else {
  set unsSolver [pw::Application begin UnstructuredSolver [list $rotateBlock]]
    set status end
    $unsSolver setStopWhenFullLayersNotMet false
    $unsSolver setAllowIncomplete true
    $unsSolver run Initialize

    # This should check the status of the initialization, however, I am not
    # sure how robust this is.
    set failed [$unsSolver getFailedEntities]
    if { [llength $failed] > 0 } {
      puts "ERROR: there was a problem initializing at least one block; aborting"
      set status abort
    }
  $unsSolver $status
  unset unsSolver
  pw::Application markUndoLevel Initialize

  # Exit if Initialize fails
  if { [string compare $status "abort"] == 0 } { exit }

  set caeType [pw::Application getCAESolver]
  set caeExtensions [pw::Application getCAESolverAttribute FileExtensions]

  puts "caeType: $caeType, caeExtensions: $caeExtensions"

  set caeExporter [pw::Application begin CaeExport [pw::Entity sort [list $rotateBlock]]]
    set status abort
    # This does not work as Pointwise's Glyph page claims it should:
    # if { $caeExporter && [$caeExporter initialize -strict -type CAE "$currentDirectory/$fileName"] }

    # TODO: for some reason, this will sometimes
    # add the proper extension, and other times it will not. E.g., CGNS files do
    # not have an extension added, but many other I have tested do.
    if { [$caeExporter initialize -strict -type CAE "$currentDirectory/$fileName"] } {
      puts "caeExporter initialize succeeded..."
      #$caeExporter setAttribute FilePrecision Double
      #$caeExporter setAttribute GridExportMeshLinkFileName "$currentDirectory/$fileName.xml"
      #$caeExporter setAttribute GridExportMeshLinkDatabaseFileName "$currentDirectory/$fileName.nmb"
      if { [$caeExporter verify] && [$caeExporter canWrite] && [$caeExporter write] } {
        puts "caeExporter {verify,canWrite,write} succeeded..."
        set status end
      } else { puts "caeExporter {verify,canWrite,write} failed..." }
    }
  $caeExporter $status
  unset caeExporter

  if { [string compare $status "end"] == 0 } {
    puts "####################################################################################################"
    if { [llength $caeExtensions] == 1 } {
      puts "Exported the rotated CAE to $currentDirectory/$fileName.$caeExtensions"
    } else {
      puts "Exported the rotated CAE to $currentDirectory/$fileName.\{[join $caeExtensions ,]\}"
    }
    puts "####################################################################################################"
  }
}

# vim: set ft=tcl:
