# Pointwise V18.3 Journal file - Wed Nov 13 15:10:39 2019

package require PWI_Glyph 3.18.3

if { $argc != 1 } {
  puts "The Pointwise project file must be passed to this script as the first
  argument"
  exit
} else {
  set pwfile [lindex $argv 0]
  puts "Opening Pointwise project file $pwfile"
}

puts "[pw::Application getVersion]"
#puts "List of supported Glyph commands"
#foreach c [lsort [pw::Application getAllCommandNames]] {
#  puts "  $c"
#}

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
  puts "Found [llength $rotateModels] models to rotate"
}

puts "Rotate models: $rotateModels"
puts "Rotate model names: $rotateModelNames"

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
  puts "Found [llength $rotatePoints] models to rotate"
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
    set rotateAngle 45

    puts "The rotation angle is $rotateAngle degrees about axis: $rotateAxis"

    # Perform rotation
    pw::Entity transform [pwu::Transform rotation -anchor $rotateAnchor $rotateAxis $rotateAngle] $m
  }

$rotateMode end
unset rotateMode
pw::Application markUndoLevel Rotate

# TODO: add support to only write out modified boundaries for verification
# before re-initializing the block(s).

set rotateBlock [pw::GridEntity getByName blk-1]
set unsSolver [pw::Application begin UnstructuredSolver [list $rotateBlock]]
  $unsSolver setStopWhenFullLayersNotMet false
  $unsSolver setAllowIncomplete true
  $unsSolver run Initialize
$unsSolver end
unset unsSolver
pw::Application markUndoLevel Initialize

set caeExporter [pw::Application begin CaeExport [pw::Entity sort [list $rotateBlock]]]
set status abort
  #if { $caeExporter && [$caeExporter initialize -strict -type CAE /Users/ehereth/Downloads/foobar.cgns] } {
  if { [$caeExporter initialize -strict -type CAE "/Users/ehereth/Downloads/foobar.cgns"] } {
    puts "caeExporter initialize succeeded..."
    $caeExporter setAttribute FilePrecision Double
    $caeExporter setAttribute GridExportMeshLinkFileName "/Users/ehereth/Downloads/foobar.xml"
    $caeExporter setAttribute GridExportMeshLinkDatabaseFileName "/Users/ehereth/Downloads/foobar.nmb"
    if { [$caeExporter verify] && [$caeExporter canWrite] && [$caeExporter write] } {
      puts "caeExporter {verify,canWrite,write} succeeded..."
      set status end
    } else { puts "caeExporter {verify,canWrite,write} failed..." }
}

$caeExporter $status
unset caeExporter
