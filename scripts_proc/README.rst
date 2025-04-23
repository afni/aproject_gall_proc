Scripts to run on the data that has only been processed with things
like:

* deobliquing and refacing (for the anatomical)

* slice timing insertion into the header files (for the EPI)

These prior processings were managed by the scripts_init/ directory
scripts.

--------------------------------------------------------------------------

**do_13_ssw2.tcsh, run_13_ssw2.tcsh**

* Run sswarper2 on the anatomical dataset to:
  * make a skullstripped (SS) version
  * estimate nonlinear alignment (warping) to a template

**do_21_ap.tcsh, run_21_ap.tcsh**

* Run afni_proc.py (AP) on the EPI and anatomical data to do the main
  processing.  This is a full FMRI processing for each subject, going
  through regression modeling APQC HTML generation.

