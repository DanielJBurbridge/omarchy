# shellcheck shell=bash
# A physical keyboard is a udev keyboard that is not the Ally's N-KEY
# controller interface (USB 0b05:1abe, including its keyboard interface)
# and not a virtual or uinput device.

gaming_device_is_physical_keyboard() {
  local props=$1 line name='' model_name='' vendor='' model='' devpath='' keyboard=false value
  while IFS= read -r line; do
    case $line in
      ID_INPUT_KEYBOARD=1) keyboard=true ;;
      ID_VENDOR_ID=* | ID_MODEL_ID=* | ID_MODEL=* | DEVPATH=* | NAME=*)
        value=${line#*=}
        value=${value#\"}
        value=${value%\"}
        case $line in
          ID_VENDOR_ID=*) vendor=$value ;;
          ID_MODEL_ID=*) model=$value ;;
          ID_MODEL=*) model_name=$value ;;
          DEVPATH=*) devpath=$value ;;
          NAME=*) name=$value ;;
        esac
        ;;
    esac
  done <<< "$props"
  [[ $keyboard == true ]] || return 1
  [[ $devpath == /devices/virtual/* ]] && return 1
  vendor=${vendor,,}
  model=${model,,}
  [[ $vendor == 0b05 && $model == 1abe ]] && return 1
  local label=${name,,} model_label=${model_name,,}
  [[ $label == *n-key* || $model_label == *n-key* ]] && return 1
  [[ $label == *uinput* || $label == *inputplumber* || $label == *ydotool* || $label == *py-evdev* ]] && return 1
  [[ $model_label == *uinput* || $model_label == *inputplumber* || $model_label == *ydotool* || $model_label == *py-evdev* ]] && return 1
  return 0
}

gaming_physical_keyboard_in() {
  local root=$1 event props
  [[ -d $root ]] || return 1
  for event in "$root"/event*; do
    [[ -e $event ]] || continue
    props=$(udevadm info --query=property -- "$event" 2>/dev/null) || continue
    gaming_device_is_physical_keyboard "$props" && return 0
  done
  return 1
}
