#!/bin/tcsh

# DESC: process anatomicals by deobliquing and refacing

# Process a single subj+ses pair. Run it from its partner run*.tcsh script.
# Run on a slurm/swarm system (like Biowulf) or on a desktop.

# ---------------------------------------------------------------------------

# use slurm? 1 = yes, 0 = no (def: use if available)
set use_slurm = $?SLURM_CLUSTER_NAME

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

# upper directories
set dir_inroot     = ${PWD:h}                        # one dir above scripts/
set dir_log        = ${dir_inroot}/logs
set dir_basic      = ${dir_inroot}/data_00_basic
set dir_deob_face  = ${dir_inroot}/data_02_deob_face

# subject directories
set sdir_basic     = ${dir_basic}/${subj}
set sdir_func      = ${sdir_basic}/func
set sdir_anat      = ${sdir_basic}/anat
set sdir_deob_face = ${dir_deob_face}/${subj}

# supplementary directory (reference data, etc.)
###set dir_suppl      = ${dir_inroot}/supplements
### set template       = ${dir_suppl}/*****

# set output directory
set sdir_out = ${sdir_deob_face}
set lab_out  = deob_face

# --------------------------------------------------------------------------
# data and control variables
# --------------------------------------------------------------------------

# dataset inputs

set dset_anat = ( ${sdir_anat}/${subj}_T1w.nii.gz )
set json_anat = ( ${sdir_anat}/${subj}_T1w.json )

# control variables

# ***** provide relevant paths to control parameters


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
        set sdir_out = /lscratch/$SLURM_JOBID/${subj}

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

# make output directory and go to it
\mkdir -p ${sdir_out}
cd ${sdir_out}

\cp ${json_anat} .

# deoblique the anat (no regrid/blur, keep coord origin)
adjunct_deob_around_origin                       \
    -input   ${dset_anat}                        \
    -prefix  ${subj}_T1w_DEOB.nii.gz

if ( ${status} ) then
    set ecode = 1
    goto COPY_AND_EXIT
endif

# reface (along with other outputs); use shell that removes more face
@afni_refacer_run                                  \
    -input      ${subj}_T1w_DEOB.nii.gz            \
    -mode_all                                      \
    -shell      afni_refacer_shell_sym_2.0.nii.gz  \
    -prefix     ${subj}_T1w

if ( ${status} ) then
    set ecode = 2
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

