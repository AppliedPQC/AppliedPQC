#!/bin/sh
# ---------------------------------------------------------------------
# Download the known-answer test vectors used by test_kat.sage.
#
# They total roughly 90 MB and are not kept in the repository.
#
#   FIPS 203/204/205 : NIST ACVP "internalProjection" files, which carry
#                      both the inputs and the expected outputs of every
#                      test case.
#   FIPS 206         : NIST has published no draft and no vectors, so
#                      FN-DSA is checked against the round-3 Falcon
#                      submission's own KAT files.
# ---------------------------------------------------------------------
set -e

cd "$(dirname "$0")"
mkdir -p vectors
cd vectors

ACVP="https://raw.githubusercontent.com/usnistgov/ACVP-Server/master/gen-val/json-files"

for d in \
    ML-KEM-keyGen-FIPS203 \
    ML-KEM-encapDecap-FIPS203 \
    ML-DSA-keyGen-FIPS204 \
    ML-DSA-sigGen-FIPS204 \
    ML-DSA-sigVer-FIPS204 \
    SLH-DSA-keyGen-FIPS205 \
    SLH-DSA-sigGen-FIPS205 \
    SLH-DSA-sigVer-FIPS205
do
    if [ -s "$d.json" ]; then
        echo "have    $d.json"
    else
        echo "fetch   $d.json"
        curl -sfLo "$d.json" "$ACVP/$d/internalProjection.json"
    fi
done

if [ -s falcon512-KAT.rsp ] && [ -s falcon1024-KAT.rsp ]; then
    echo "have    falcon{512,1024}-KAT.rsp"
else
    echo "fetch   falcon-round3.zip (Falcon KATs for FIPS 206)"
    curl -sfLo falcon-round3.zip "https://falcon-sign.info/falcon-round3.zip"
    python3 - <<'PY'
import zipfile
z = zipfile.ZipFile('falcon-round3.zip')
for n in ('falcon-round3/KAT/falcon512-KAT.rsp',
          'falcon-round3/KAT/falcon1024-KAT.rsp'):
    open(n.split('/')[-1], 'wb').write(z.read(n))
PY
    rm -f falcon-round3.zip
fi

echo
echo "Test vectors are in $(pwd)."
