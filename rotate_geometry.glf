# Pointwise V18.3 Journal file - Wed Nov 13 15:10:39 2019

package require PWI_Glyph 3.18.3

#TODO: create a cleaner usage string to print here
if { $argc < 2 } {
  puts "The Pointwise project file must be passed to this script as the first
  argument and a rotation angle as the second. You may pass the --verify
  argument as well to have this script export the rotated boundaries only for
  initial verification."
  exit
} else {
  puts "Calling $argv0 with the following arguments: $argv"
  # Look for --verify in argument list
  set verify false
  if { [lsearch $argv "--verify"] != -1 } {
    puts "Running in verify mode"
    set verify true
  }

  set pwfile [lindex $argv 0]
  puts "Opening Pointwise project file $pwfile"
  # TODO: support multiple rotation angles in case models need to be rotated
  # differing amounts.
  set rotateAngle [lindex $argv 1]
  puts "Rotating model(s) by $rotateAngle degrees"
}

puts "[pw::Application getVersion]"

# Set current working directory to be used as the base for saving files
set currentDirectory [pwd]

puts "loading $pwfile..."
pw::Application reset
pw::Application load "$pwfile"
puts "loaded $pwfile..."

pw::Application setUndoMaximumLevels 20

# Get a list of all models in the project
set models [pw::Database getAll -type pw::Model]

# Initialize empty lists for the models to be rotated
set rotateModels [list]
set rotateModelNames [list]

# Look for any model(s) named like rotate-* (rotate-1, rotate-2, etc.)
foreach m $models {
  set name [$m getName]
  if { [string match "rotate-*" $name] } {
    lappend rotateModels $m
    lappend rotateModelNames $name
  }
}

if { [llength $rotateModels] == 0 } {
  puts "ERROR: there must be at least one model named rotate-*"
  exit
} else {
  puts "Found [llength $rotateModels] [expr { [llength $rotateModels] > 1 ? "models" : "model" }] to rotate"
}

puts "Rotate models: $rotateModels"
puts "Rotate model names: $rotateModelNames"

# Create file name template; I do not like this name string, but it should be
# clear albeit ugly
set fileName [lindex  [split $pwfile .] 0]
foreach m $rotateModelNames {
  lappend fileName $m $rotateAngle
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
foreach m $rotateModels {
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

puts "Rotate points: $rotatePoints"
puts "Rotate point names: $rotatePointNames"

set rotateMode [pw::Application begin Modify $rotateModels]

  set pointIndex 0
  foreach m $rotateModels {

    # Get axis point coordinates
    set pt1 [lindex $rotatePoints $pointIndex]
    set pt1Coord [$pt1 getXYZ]
    incr pointIndex
    set pt2 [lindex $rotatePoints $pointIndex]
    set pt2Coord [$pt2 getXYZ]
    incr pointIndex

    puts "Rotating model $m (named [$m getName]) about the points:\
          $pt2 and $pt2 (named [$pt1 getName] at $pt1Coord and [$pt2 getName] at $pt2Coord)"

    # Define rotation axis
    set rotateAxis [pwu::Vector3 normalize [pwu::Vector3 subtract $pt1Coord $pt2Coord]]
    set rotateAnchor $pt1Coord

    puts "The rotation angle is $rotateAngle degrees about axis: $rotateAxis"

    # Perform rotation
    pw::Entity transform [pwu::Transform rotation -anchor $rotateAnchor $rotateAxis $rotateAngle] $m
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
  # TODO: check for success/failure after this and handle result
  set unsSolver [pw::Application begin UnstructuredSolver [list $rotateBlock]]
    $unsSolver setStopWhenFullLayersNotMet false
    $unsSolver setAllowIncomplete true
    $unsSolver run Initialize
  $unsSolver end
  unset unsSolver
  pw::Application markUndoLevel Initialize

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

  puts "####################################################################################################"
  if { [llength $caeExtensions] == 1 } {
    puts "Exported the rotated CAE to $currentDirectory/$fileName.$caeExtensions"
  } else {
    puts "Exported the rotated CAE to $currentDirectory/$fileName.\{[join $caeExtensions ,]\}"
  }
  puts "####################################################################################################"
}

# vim: set ft=tcl:
