#!/bin/tcsh

# DESC: (group level) run 3dttest++ (1-sample) on set of subj stats results

# Process a single group. Run it from its partner run*.tcsh script.
# Run on a slurm/swarm system (like Biowulf) or on a desktop.

# ---------------------------------------------------------------------------

# use slurm? 1 = yes, 0 = no (def: use if available)
set use_slurm = 0 ### $?SLURM_CLUSTER_NAME

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
set cond           = $1
set cmd            = ttest.1grp
set ap_label       = 21_ap                           # inputs: subj results
set grp_label      = group_ana.${cmd}.${cond}

# upper directories
set dir_inroot     = ${PWD:h}                        # one dir above scripts/
set dir_log        = ${dir_inroot}/logs
set dir_basic      = ${dir_inroot}/data_03_slice_tree  # not usual 00_basic
set dir_ssw        = ${dir_inroot}/data_13_ssw
set dir_ap         = ${dir_inroot}/data_${ap_label}

set dir_grpana     = ${dir_ap}/${grp_label}        # outdir for group analysis

# subject directories
###set sdir_basic     = ${dir_basic}/${subj}
###set sdir_func      = ${sdir_basic}/func
###set sdir_anat      = ${sdir_basic}/anat
###set sdir_ssw       = ${dir_ssw}/${subj}
###set sdir_ap        = ${dir_ap}/${subj}

# supplementary directory (reference data, etc.)
###set dir_suppl      = ${dir_inroot}/supplements
set template       = MNI152_2009_template_SSW.nii.gz

# *** set output directory
set sdir_out = ${dir_grpana}
set lab_out  = ${sdir_out:t}

# --------------------------------------------------------------------------
# data and control variables
# --------------------------------------------------------------------------

# dataset inputs

# list of all stats dsets, abs path
set all_dsets = ( `find ${dir_ap} -name "stats.sub-*_REML+tlrc.HEAD" | sort` )
# ... and check if the list of dsets is empty or not
if ( ${#all_dsets} == 0 ) then
    echo "** ERROR: did not find any stats dsets to input"
    goto BAD_EXIT
endif

# list of all subj mask dsets, abs path
set all_mask = ( `find ${dir_ap} -name "mask_epi_anat.sub-*+tlrc.HEAD" | sort` )
# ... and check if the list of mask dsets is empty or not
if ( ${#all_mask} == 0 ) then
    echo "** ERROR: did not find any mask dsets to input"
    goto BAD_EXIT
endif

# set beta, and verify it exists (all stats label sets should be the same)
set beta = "${cond}#0_Coef"
set idx  = `3dinfo -label2index ${beta} ${all_dsets[1]}`
# ... and check if the idx value is empty or not
if ( ${#idx} == 0 ) then
    echo "** ERROR: beta label '${beta}' doesn't appear in stats dset list"
    goto BAD_EXIT
endif

# copy ref dset into group ana output dir (not necessary with env vars...)
set dset_ref = `@FindAfniDsetPath -full_path -append_file ${template}`
# ... and check if the idx value is empty or not
if ( ${#dset_ref} == 0 ) then
    echo "** ERROR: template dset '${template}' could not be found"
    goto BAD_EXIT
endif

# control variables
set tt_script = run.${cmd}.${cond}.tcsh

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
        set sdir_out = /lscratch/$SLURM_JOBID/${cond} ### ${subj}

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

# make group level masks, for later reference (we calc everywhere)

echo "====== making intersection, mean and 70% masks"
echo "++ Found ${#all_mask} mask dsets"

3dTstat                                                                      \
    -mean                                                                    \
    -prefix  group_mask.mean.nii.gz                                          \
    ${all_mask}

3dmask_tool                                                                  \
    -prefix  group_mask.70perc.nii.gz                                        \
    -frac    0.7                                                             \
    -input   ${all_mask}

3dmask_tool                                                                  \
    -prefix  group_mask.inter.nii.gz                                         \
    -frac    1.0                                                             \
    -input   ${all_mask}

if ( ${status} ) then
    set ecode = 1
    goto COPY_AND_EXIT
endif

# copy ref dset to the dir

\cp ${dset_ref} .

if ( ${status} ) then
    set ecode = 2
    goto COPY_AND_EXIT
endif

# create gen_group_command script
set run_script = ggc.cmd.${cmd}.${cond}

cat << EOF >! ${run_script}

# GGC: generate group-level command
# 
# Notes:
# + just processing all subj at the moment
#   - could add subsets with '-dset_sid_list ..'
#   - could add drop set with '-dset_sid_omit_list ..'

gen_group_command.py                                                         \
    -command        3dttest++                                                \
    -write_script   ${tt_script}                                             \
    -dsets          ${all_dsets}                                             \
    -subj_prefix    sub-                                                     \
    -set_labels     ${cond}                                                  \
    -subs_betas     "${beta}"                                                \
    -prefix         ${cmd}.${cond}.nii.gz                                    \
    -verb           2                                                        \
    |& tee output.${run_script}.txt

EOF

if ( ${status} ) then
    set ecode = 3
    goto COPY_AND_EXIT
endif


# execute GGC command to make processing script (already logs)
tcsh -xef ${run_script} 

if ( ${status} ) then
    set ecode = 4
    goto COPY_AND_EXIT
endif


# execute the group ana cmd
time tcsh -xef ${tt_script} |& tee output.${tt_script}

if ( ${status} ) then
    set ecode = 5
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

