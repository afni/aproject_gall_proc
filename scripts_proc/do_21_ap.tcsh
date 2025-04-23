#!/bin/tcsh

# DESC: run afni_proc.py (AP) on the EPI and anatomical data

# Process a single subj. Run it from its partner run*.tcsh script.
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
set dir_basic      = ${dir_inroot}/data_03_slice_tree  # not usual 00_basic
set dir_ssw2       = ${dir_inroot}/data_13_ssw2
set dir_ap         = ${dir_inroot}/data_21_ap

# subject directories
set sdir_basic     = ${dir_basic}/${subj}
set sdir_func      = ${sdir_basic}/func
set sdir_anat      = ${sdir_basic}/anat
set sdir_ssw2      = ${dir_ssw2}/${subj}
set sdir_ap        = ${dir_ap}/${subj}

# supplementary directory (reference data, etc.)
###set dir_suppl      = ${dir_inroot}/supplements
set template       = MNI152_2009_template_SSW.nii.gz

# *** set output directory
set sdir_out = ${sdir_ap}
set lab_out  = ${sdir_out:t}

# --------------------------------------------------------------------------
# data and control variables
# --------------------------------------------------------------------------

# dataset inputs

set taskname  = "Move"

set dset_epi  = ( ${sdir_func}/${subj}*task-${taskname}*bold*.nii.gz )

set anat_cp       = ( ${sdir_ssw2}/anatSS.${subj}.nii* )
set anat_skull    = ( ${sdir_ssw2}/anatU.${subj}.nii* )

set dsets_NL_warp = ( ${sdir_ssw2}/anatQQ.${subj}.nii*         \
                      ${sdir_ssw2}/anatQQ.${subj}.aff12.1D     \
                      ${sdir_ssw2}/anatQQ.${subj}_WARP.nii*  )

# control variables

set nt_rm         = 0       # number of time points to remove at start
set blur_size     = 3       # blur size to apply 
set final_dxyz    = 1.75    # final voxel size (isotropic dim)
set cen_motion    = 0.3     # censor threshold for motion (enorm) 
set cen_outliers  = 0.05    # censor threshold for outlier frac

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

# create command script
set run_script = ap.cmd.${subj}

cat << EOF >! ${run_script}

# AP, example 2: task FMRI
# 
# task-pamenc_bold.json shows slice timing of alt+z2 (missing
# from nii.gz) blur in mask, and use higher 6 mm FWHM (voxels are
# 3x3x4)

# NL alignment

afni_proc.py                                                                 \
    -subj_id                  ${subj}                                        \
    -dsets                    ${dset_epi}                                    \
    -copy_anat                ${anat_cp}                                     \
    -anat_has_skull           no                                             \
    -anat_follower            anat_w_skull anat ${anat_skull}                \
    -blocks                   tshift align tlrc volreg mask blur scale       \
                              regress                                        \
    -radial_correlate_blocks  tcat volreg regress                            \
    -tcat_remove_first_trs    ${nt_rm}                                       \
    -align_unifize_epi        local                                          \
    -align_opts_aea           -giant_move -cost lpc+ZZ -check_flip           \
    -tlrc_base                ${template}                                    \
    -tlrc_NL_warp                                                            \
    -tlrc_NL_warped_dsets     ${dsets_NL_warp}                               \
    -volreg_align_to          MIN_OUTLIER                                    \
    -volreg_align_e2a                                                        \
    -volreg_tlrc_warp                                                        \
    -volreg_warp_dxyz         ${final_dxyz}                                  \
    -volreg_compute_tsnr      yes                                            \
    -mask_epi_anat            yes                                            \
    -blur_size                ${blur_size}                                   \
    -regress_stim_times       ${sdir_func}/stim_imagine.txt                  \
                              ${sdir_func}/stim_press.txt                    \
    -regress_stim_labels      imagine  press                                 \
    -regress_basis_multi      'BLOCK(20,1)'  'BLOCK(20,1)'                   \
    -regress_motion_per_run                                                  \
    -regress_censor_motion    ${cen_motion}                                  \
    -regress_censor_outliers  ${cen_outliers}                                \
    -regress_compute_fitts                                                   \
    -regress_fout             no                                             \
    -regress_opts_3dD         -jobs 2                                        \
                              -gltsym 'SYM: imagine -press'                  \
                              -glt_label 1 I-P                               \
                              -gltsym 'SYM: 0.5*imagine +0.5*press'          \
                              -glt_label 2 meanIP                            \
    -regress_3dD_stop                                                        \
    -regress_reml_exec                                                       \
    -regress_make_ideal_sum   sum_ideal.1D                                   \
    -regress_est_blur_errts                                                  \
    -regress_run_clustsim     no                                             \
    -html_review_style        pythonic

EOF

if ( ${status} ) then
    set ecode = 1
    goto COPY_AND_EXIT
endif


# execute AP command to make processing script
tcsh -xef ${run_script} |& tee output.ap.cmd.${subj}

if ( ${status} ) then
    set ecode = 2
    goto COPY_AND_EXIT
endif


# execute the proc script, saving text info
time tcsh -xef proc.${subj} |& tee output.proc.${subj}

if ( ${status} ) then
    set ecode = 3
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

