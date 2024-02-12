#!/bin/bash

VALID_ARGS=$(getopt -o f:hor --long file:,help,skip-opt,run -- "$@")

if [[ $? -ne 0 ]]; then
    exit 1;
fi

eval set -- "$VALID_ARGS"
while [ : ]; do
  case "$1" in
    -f | --file)
        _filename="$2"
        shift 2
        ;;
    -h | --help)
        echo 'LaTeXCompilerDockerImage'
        echo 'A Docker image with all the tools ready to compile a latex project with pdflatex and bibtex.'
        echo
        echo 'Usage:'
        echo '  docker run -t latex-img:latest -v <project_root>/:/data/ (-f | --file) <tex_file_name> [-o --skip-opt]'
        echo '  docker run -t latex-img:latest (-h | --help)'
        echo '  docker run -t latex-img:latest (-r | --run)'
        echo
        echo 'Options:'
        echo '  -f --file       The main .tex file name without the suffix.'
        echo '  -h --help       Show this screen. All other options are ignored.'
        echo '  -o --skip-opt   Skip the optimization of the file.'
        echo '  -r --run        Open a bash shell in the container.'
        exit 0
        ;;
    -o | --skip-opt)
        _skip_opt=true
        shift
        ;;
    -r | --run)
        bash
        exit 0
        ;;
    --) shift;
        break
        ;;
  esac
done

_print() {
  local _color_num
  case "$1" in
    info)
        _color_num=4
        ;;
    success)
        _color_num=2
        ;;
    fail)
        _color_num=1
        ;;
    *)
        _color_num=4
       ;;
  esac

  local _main_msg=${2:-}
  local _supp_msg=${3:-}

  if [ -n "$_supp_msg" ]; then
    _supp_msg=" - $_supp_msg"
  fi

  echo -e "\n\e[1;3${_color_num}m[${_main_msg}]${_supp_msg}\e[0m"
}

if [ -z "$_filename" ]; then
  _print fail 'The --file argument must be set. Aborting...'
  exit 1
fi

_filename_tex="$_filename".tex
_filename_pdf="$_filename".pdf
_filename_opt_pdf="$_filename"_opt.pdf

if [ -f /data/"$_filename_tex" ]; then

  # Copy latex to temp folder and move there
  cp -r /data /data_tmp
  cd /data_tmp || exit

  _print info "Compiling $_filename_tex to $_filename_pdf..."

  _pdflatex_command() {
    pdflatex -shell-escape -interaction=nonstopmode -output-directory . "$1"
  }

  _bibtex_command() {
    bibtex "$1"
  }

  _build_commands_sequence=( _pdflatex_command _bibtex_command _pdflatex_command _pdflatex_command )

  # Start of the compilation
  for _command_index in "${!_build_commands_sequence[@]}" ; do
    _command="${_build_commands_sequence[$_command_index]}"

    _print info "$(( _command_index + 1 ))/${#_build_commands_sequence[@]}" "$(declare -f "$_command" | sed -e '1d' -e '2d' -e '$d' -e '3s/^[[:space:]]*//')"

    $_command "$_filename"
    _status_code="$?"

    if $_command "$_filename"; then
      _print fail "Compilation failed with code $_status_code!" 'Aborting...'
      exit "$_status_code"
    fi
  done

  # Copy compiled pdf back in shared volume
  cp /data_tmp/"$_filename_pdf" /data/"$_filename_pdf"

  _print success 'Document compiled!'

  # Optimization
  if [ "$_skip_opt" = true ]; then
    # Skipping optimization
    _print info 'Skipping optimization.'
    exit 0
  fi

  _print info "Optimizing $_filename_pdf to $_filename_opt_pdf..."

  if ! _status_code=$(ps2pdf "$_filename_pdf" "$_filename_opt_pdf"); then
    _print fail "Optimization failed with code $_status_code!" 'Aborting...'
    exit "$_status_code"
  fi

  _size_unit=kB
  (( _org_size = $(wc -c "$_filename_pdf" | cut -d' ' -f1)/1000 ))
  (( _opt_size = $(wc -c "$_filename_opt_pdf" | cut -d' ' -f1)/1000 ))
  (( _opt_gain = 100*(_org_size - _opt_size)/_org_size )) || true

  if [ "$_org_size" -gt 1000 ]; then
    _size_unit=MB
    (( _org_size = _org_size/1000 ))
    (( _opt_size = _opt_size/1000 ))
  fi

  # Copy optimized pdf back in shared volume
  cp /data_tmp/"$_filename_opt_pdf" /data/"$_filename_opt_pdf"

  _print success 'Optimization successful!' "From ${_org_size} ${_size_unit} to ${_opt_size} ${_size_unit} (-$_opt_gain%)"

  exit 0

else
  _print fail "File $_filename_tex not found" 'Aborting...'
  exit 1
fi
