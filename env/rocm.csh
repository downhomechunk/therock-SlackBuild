#!/bin/csh
## Set up t/csh environment for ROCM

# Base path
setenv ROCM_PATH /opt/rocm

# HIP base path
setenv HIP_PATH /opt/rocm

# Follow other profile.d CSH scripts and place
# new PATH element at the end of PATH.
setenv PATH ${PATH}:${ROCM_PATH}/bin
