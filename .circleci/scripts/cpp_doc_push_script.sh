# =================== The following code **should** be executed inside Docker container ===================

# Install dependencies
sudo apt-get -y update
sudo apt-get -y install expect-dev

# This is where the local pytorch install in the docker image is located
pt_checkout="/var/lib/jenkins/workspace"

# Since we're cat-ing this file, we need to escape all $'s
echo "cpp_doc_push_script.sh: Invoked with $*"

# for statements like ${1:-${DOCS_INSTALL_PATH:-docs/}}
# the order of operations goes:
#   1. Check if there's an argument $1
#   2. If no argument check for environment var DOCS_INSTALL_PATH
#   3. If no environment var fall back to default 'docs/'

# NOTE: It might seem weird to gather the second argument before gathering the first argument
#       but since DOCS_INSTALL_PATH can be derived from DOCS_VERSION it's probably better to
#       try and gather it first, just so we don't potentially break people who rely on this script
# Argument 2: What version of the Python API docs we are building.
version="${2:-${DOCS_VERSION:-master}}"
if [ -z "$version" ]; then
echo "error: cpp_doc_push_script.sh: version (arg2) not specified"
  exit 1
fi

# Argument 1: Where to copy the built documentation for Python API to
# (pytorch.github.io/$install_path)
install_path="${1:-${DOCS_INSTALL_PATH:-docs/${DOCS_VERSION}}}"
if [ -z "$install_path" ]; then
echo "error: cpp_doc_push_script.sh: install_path (arg1) not specified"
  exit 1
fi

is_main_doc=false
if [ "$version" == "master" ]; then
  is_main_doc=true
fi

echo "install_path: $install_path  version: $version"

# ======================== Building PyTorch C++ API Docs ========================

echo "Building PyTorch C++ API docs..."

# Clone the cppdocs repo
rm -rf cppdocs
git clone https://github.com/pytorch/cppdocs

set -ex

# Generate ATen files
pushd "${pt_checkout}"
pip install -r requirements.txt
time python -m torchgen.gen \
  -s aten/src/ATen \
  -d build/aten/src/ATen

# Copy some required files
cp torch/_utils_internal.py tools/shared

# Generate PyTorch files
time python tools/setup_helpers/generate_code.py \
  --native-functions-path aten/src/ATen/native/native_functions.yaml \
  --tags-path aten/src/ATen/native/tags.yaml

# Build the docs
pushd docs/cpp
pip install -r requirements.txt
time make VERBOSE=1 html -j

popd
popd

pushd cppdocs

# Purge everything with some exceptions
mkdir /tmp/cppdocs-sync
mv _config.yml README.md /tmp/cppdocs-sync/
rm -rf *

# Copy over all the newly generated HTML
cp -r "${pt_checkout}"/docs/cpp/build/html/* .

# Copy back _config.yml
rm -rf _config.yml
mv /tmp/cppdocs-sync/* .

# Make a new commit
git add . || true
git status
git config user.email "soumith+bot@pytorch.org"
git config user.name "pytorchbot"
# If there aren't changes, don't make a commit; push is no-op
git commit -m "Generate C++ docs from pytorch/pytorch@${GITHUB_SHA}" || true
git status

if [[ "${WITH_PUSH:-}" == true ]]; then
  # push to a temp branch first to trigger CLA check and satisfy branch protections
  git push -u origin HEAD:pytorchbot/temp-branch-cpp -f
  sleep 30
  git push -u origin
fi

popd
# =================== The above code **should** be executed inside Docker container ===================
