#!/bin/tcsh

# DESC: GTKYD check (will **disable** slurm/swarm for this cmd)

# Process a single subj+ses pair. Run it from its partner run*.tcsh script.
# Run on a slurm/swarm system (like Biowulf) or on a desktop.

# ---------------------------------------------------------------------------

# use slurm? 1 = yes, 0 = no (def: use if available)
set use_slurm = 0 ###$?SLURM_CLUSTER_NAME

# ----------------------------- biowulf-cmd ---------------------------------
if ( $use_slurm ) then
    # load modules: ***** add any other necessary ones
    source /etc/profile.d/modules.csh
    module load afni

    # set N_threads for OpenMP
    setenv OMP_NUM_THREADS $SLURM_CPUS_ON_NODE
endif
# ---------------------------------------------------------------------------

# initial exit code; we don't exit at fail, to copy partial results back
set ecode = 0

# ***** set relevant environment variables
setenv AFNI_COMPRESSOR GZIP           # zip BRIK dsets

# ---------------------------------------------------------------------------
# top level definitions (constant across demo)
# ---------------------------------------------------------------------------

# labels
set subj           = $1

# for convenience, "full" subj ID and path
set subjid = ${subj} ###_${ses}
set subjpa = ${subj} ###/${ses}

# upper directories
set dir_inroot     = ${PWD:h}                        # one dir above scripts/
set dir_log        = ${dir_inroot}/logs
set dir_basic      = ${dir_inroot}/data_00_basic
set dir_gtkyd      = ${dir_inroot}/data_01_gtkyd

# set output directory
set sdir_out = ${dir_gtkyd}
set lab_out  = gtkyd

# --------------------------------------------------------------------------
# data and control variables
# --------------------------------------------------------------------------

# dataset inputs

# jump to group dir of unproc'essed data
cd ${dir_basic}
set all_epi  = `find ./sub* -name "sub*task*bold*.nii.gz" | cut -b3- | sort`
set all_anat = `find ./sub* -name "sub*T1w*.nii.gz" | cut -b3- | sort`
cd -


# check available N_threads and report what is being used
set nthr_avail = `afni_system_check.py -disp_num_cpu`
set nthr_using = `afni_check_omp`

echo "++ INFO: Using ${nthr_using} of available ${nthr_avail} threads"

# ----------------------------- biowulf-cmd --------------------------------
if ( $use_slurm ) then
    # try to use /lscratch for speed; store "real" output dir for later copy
    if ( -d /lscratch/$SLURM_JOBID ) then
        set usetemp  = 1
        set sdir_BW  = ${sdir_out}
        set sdir_out = /lscratch/$SLURM_JOBID/${subjid}

        # prep for group permission reset
        \mkdir -p ${sdir_BW}
        set grp_own  = `\ls -ld ${sdir_BW} | awk '{print $4}'`
    else
        set usetemp  = 0
    endif
endif
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# run programs
# ---------------------------------------------------------------------------

# make output directory
\mkdir -p ${sdir_out}

# jump to same dir_basic as above so read-in file paths are the same
cd ${dir_basic}

# ----- check EPI

# make table+supplements of all dsets
gtkyd_check.py                                       \
    -do_minmax                                       \
    -infiles    ${all_epi}                           \
    -outdir     ${sdir_out}/all_epi

if ( ${status} ) then
    set ecode = 1
    goto COPY_AND_EXIT
endif

# query supplemental files for specific properties
gen_ss_review_table.py                               \
    -infiles          ${sdir_out}/all_epi/dset*txt   \
    -report_outliers  'subject ID'     SHOW          \
    -report_outliers  'av_space'       EQ "+tlrc"    \
    -report_outliers  'n3'             VARY          \
    -report_outliers  'nv'             VARY          \
    -report_outliers  'datum'          VARY          \
    |& tee ${sdir_out}/all_epi_gssrt.dat

if ( ${status} ) then
    set ecode = 2
    goto COPY_AND_EXIT
endif

# ----- check anat

# make table+supplements of all dsets
gtkyd_check.py                                       \
    -do_minmax                                       \
    -infiles    ${all_anat}                          \
    -outdir     ${sdir_out}/all_anat

if ( ${status} ) then
    set ecode = 3
    goto COPY_AND_EXIT
endif

# query supplemental files for specific properties
gen_ss_review_table.py                               \
    -infiles          ${sdir_out}/all_anat/dset*txt  \
    -report_outliers  'subject ID'     SHOW          \
    -report_outliers  'is_oblique'     GT 0          \
    -report_outliers  'obliquity'      GT 0          \
    -report_outliers  'av_space'       EQ "+tlrc"    \
    -report_outliers  'n3'             VARY          \
    -report_outliers  'nv'             VARY          \
    -report_outliers  'datum'          VARY          \
    |& tee ${sdir_out}/all_anat_gssrt.dat

if ( ${status} ) then
    set ecode = 4
    goto COPY_AND_EXIT
endif

echo "++ FINISHED ${lab_out}"

# ---------------------------------------------------------------------------

COPY_AND_EXIT:

# ----------------------------- biowulf-cmd --------------------------------
if ( $use_slurm ) then
    # if using /lscratch, copy back to "real" location
    if( ${usetemp} && -d ${sdir_out} ) then
        echo "++ Used /lscratch"
        echo "++ Copy from: ${sdir_out}"
        echo "          to: ${sdir_BW}"
        \cp -pr   ${sdir_out}/* ${sdir_BW}/.

        # reset group permission
        chgrp -R ${grp_own} ${sdir_BW}
    endif
endif
# ---------------------------------------------------------------------------

if ( ${ecode} ) then
    echo "++ BAD FINISH: ${lab_out} (ecode = ${ecode})"
else
    echo "++ GOOD FINISH: ${lab_out}"
endif

exit ${ecode}

