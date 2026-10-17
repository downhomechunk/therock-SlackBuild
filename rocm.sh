export ROCM_PATH=${ROCM_PATH:-/opt/rocm}
export HIP_PATH=${HIP_PATH:-/opt/rocm}
case ":$PATH:" in
  *":$ROCM_PATH/bin:"*) ;;
  *) export PATH="$PATH:$ROCM_PATH/bin" ;;
esac