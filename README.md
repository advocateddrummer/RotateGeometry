# RotateGeom

This Pointwise Glyph script is used to rotate specific geometry in a Pointwise
project and re-initialize the volume block, all from the CLI. It **does not**
modify the Pointwise project file (.pw file), it _only_ modifies the project in
memory and exports the resulting CAE file.

In its current state, it must be run with a Pointwise project file as the first
argument and the rotation amount, in degrees, specified as the second argument.
Optionally, `--verify` may be passed at the end and the script will spit out
only the boundaries, after rotation, so the user can verify that the script is
doing what it is supposed to before actually initializing the volume block.
Also, the `--verbose`/`-v` parameter may be provided at the command line to
cause the script to report more about its progress etc.

Currently, any geometry models that need to be rotated must be named
_rotate-*_, i.e., _rotate-1_, _rotate-2_, etc. Furthermore, two database points
per model which define the axis of rotation for the model, must be defined,
named _rotate-*-point{1,2}_, i.e., _rotate-1-point-1_ and _rotate-1-point-2_, etc.
So, if there is a model named _rotate-1_, there must be two points, named
_rotate-1-point-1_ and _rotate-1-point-2_; the _rotate-1_ model will be rotated
about the axis defined by the two points by the user specified number of
degrees.

* **NOTE: all domains assocated with any rotated geometry _must_ be projected
  onto the geometry it is assocated with or this will not work.**

Lastly, the block, (or blocks, but this is not yet implemented), that contain
the rotated geometry must be named _rotate-block-*_. This block(s) will be
selected and re-initialized after the models are rotated. Currently, the only
block re-initialized is the block named _rotate-block-1_.

* **TODO: Support multiple angles specified, one per model, at the command line.**

## Usage

This script may be run in batch mode as follows:
~~~sh
/path/to/pointwise -b /path/to/this/glyph/script [args] pwfile angle
~~~
