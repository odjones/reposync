#!/usr/bin/bash

# update-repos (v1.05) by Oliver Jones, July 2021
#
# Usage:
#
# update-repos clean : Deletes all repository caches; fetches, creates and updates repos from scratch.
# or
# update-repos       : Updates all repository caches; updates repos according to changes (quicker).
#

# Configuration file for repositories
REPOCFG="/etc/yum-reposync.conf"

# Base directory for repositories
BASEDIR="/var/www/html/rpms"

# Get repositories configuration directory
REPODIR=`sed -n 's:reposdir=\(.*\):\1:p' ${REPOCFG}`

# Check if repository directory is non-standard
if [ "${REPODIR}" != "/etc/yum.repos.d" ]; then

    # Check if redhat.repo needs to be refreshed
    if [ -f "${REPODIR}/redhat.repo" ]; then

        # Get current Red Hat system entitlement
        RHLIC=`basename /etc/pki/entitlement/* | sed '1q' | sed -e 's:^\([0-9]*\).*:\1:'`

        # Refresh entitlement references in redhat.repo if they are not found
        grep -q "${RHLIC}" ${REPODIR}/redhat.repo || sed -i "s:\(/etc/pki/entitlement/\)\([0-9]*\)\(.*\):\1${RHLIC}\3:" ${REPODIR}/redhat.repo

    fi

fi

# Check if repository data needs to be cleaned
if [ $# -gt 0 ] && [ "$1" == "clean" ]; then

    # Set clean flag
    CLEAN=1

    # Clean RPMs
    rm -rf ${BASEDIR}/*

    # Clean yum cache
    yum clean all >/dev/null
    rm -rf /var/cache/yum

fi

# Enter base directory for processing
pushd ${BASEDIR} >/dev/null

# Check that the base directory could be reached
if [ "$?" == 0 ]; then

    # Fetch repository data
    reposync --config=${REPOCFG} --gpgcheck --plugins --source --downloadcomps --download-metadata --quiet --download_path=${BASEDIR}/

    # Check that the repository sync could be completed
    if [ "$?" == 0 ]; then

        # Process each repository
        for REPO in *; do

            # Test clean flag
            if [ "${CLEAN}" == 1 ]; then

                # Check if group information is present
                if [ -f ${BASEDIR}/${REPO}/comps.xml ]; then

                    # Create repository information from scratch with groups
                    createrepo --quiet ${BASEDIR}/${REPO} --groupfile comps.xml >/dev/null

                else

                    # Create repository information from scratch
                    createrepo --quiet ${BASEDIR}/${REPO} >/dev/null

                fi

            else

                # Check if group information is present
                if [ -f ${BASEDIR}/${REPO}/comps.xml ]; then

                    # Update repository information with groups
                    createrepo --quiet ${BASEDIR}/${REPO} --groupfile comps.xml --update >/dev/null

                else

                    # Update repository information
                    createrepo --quiet ${BASEDIR}/${REPO} --update >/dev/null

                fi

            fi

            # Preen expired update information, just in case one or more prior invocations did not complete successfully
            find ${BASEDIR}/${REPO} -maxdepth 1 -name '*-updateinfo.xml.gz' -printf "%T@#%p\n" | sort -rn | sed -e '1d;s:^.*#:rm :' | bash

            # Test for update information
            if [ -f ${BASEDIR}/${REPO}/*updateinfo.xml.gz ]; then

                # Unzip update information
                gunzip ${BASEDIR}/${REPO}/*updateinfo.xml.gz

                # Check if file-to-be-renamed already exists
                if [ -f ${BASEDIR}/${REPO}/repodata/updateinfo.xml ]; then

                    # Clobber it
                    rm -f ${BASEDIR}/${REPO}/repodata/updateinfo.xml

                fi

                # Move it into place
                mv ${BASEDIR}/${REPO}/*updateinfo.xml ${BASEDIR}/${REPO}/repodata/updateinfo.xml

                # Find existing update information in repodata
                for UPDATE in ${BASEDIR}/${REPO}/repodata/*updateinfo.xml.gz; do

                    # Clobber it
                    rm -f ${UPDATE}

                done

                # Insert the extra checksum information into the repo
                modifyrepo ${BASEDIR}/${REPO}/repodata/updateinfo.xml ${BASEDIR}/${REPO}/repodata >/dev/null

            fi
    
        done

    else

        # Inform user of/log sync failure
        echo "ERROR: Could not sync repository. Post-processing has not been performed."

        # Restore original directory
        popd >/dev/null

        # Exit with error
        exit 1

    fi

    # Restore original directory
    popd >/dev/null

else

    # Inform user of/log directory change failure
    echo "ERROR: Could not change directory to ${BASEDIR} for repository processing."

    # Exit with error
    exit 1

fi
