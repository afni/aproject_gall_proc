Scripts to run on the raw, unprocessed data.

--------------------------------------------------------------------------

**do_01_gtkyd.tcsh, run_01_gtkyd.tcsh**

* Get To Know Your Data, by checking sets of the EPI and anatomical data
  for consistency, as well as possible issues to deal with.

**do_02_deob_face.tcsh, run_02_deob_face.tcsh**

* The anatomical has obliquity and the original face still
  present. So, this script does two things. First, it purges obliquity
  from the anatomical *while retaining the location of the coordinate
  origin and also not regridding/blurring the data*. Then it refaces
  the data, replacing the face with an anonymous, blurred version and
  removing ears.

