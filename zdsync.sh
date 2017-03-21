#! /bin/bash
PATH=/opt/zdsync/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

### FUNCTIONS

errcho() {
	printf "%s\n" "$*" >&2;
}

function usage {
	echo "Usage: $0 [OPTION]... SourceDataset TargetDataset"
	echo ""
	echo "Options: "
	echo "-s, --sourceShell           specify the source shell to use"
	echo "-t, --targetShell           specify the target shell to use"
	echo "-p, --prefix                specify the prefix to use"
	echo "-k, --keepSource            keep the sync snapshot on the source datset"
	echo "-c, --timestamp             sets the 'current time' of the script (unix timestamp)"
}

### DEFAULTS

SourceShell="bash -c"
SourceDataset="storage"

TargetShell="bash -c"
TargetDataset="storage/backup/some-backup"

SyncSnapshot="zdsync-"
KeepSource=false
CurrentTime=$(date +%s)

while [ "$3" != "" ]; do
	case $1 in
		-s | --sourceShell )
			shift
			SourceShell=$1
		;;
		-t | --targetShell )
			shift
			TargetShell=$1
		;;
		-p | --prefix )
			shift
			SyncSnapshot="$1-$SyncSnapshot"
		;;
		-c | --timestamp )
			shift
			CurrentTime="$1"
		;;
		-k | --keepSource )
			KeepSource=true
		;;
		-h | --help )
			usage
			exit
		;;
		* )
			usage
			exit 1
	esac
	shift
done

if [ "$1" == "" ] || [ "$2" == "" ]; then
	usage
	exit 1
fi
SourceDataset="$1"
TargetDataset="$2"


### Find Latest Snapshots on Dataset
FullSnapshot=false
LastTargetSnapshot=$($TargetShell "bash -o pipefail -c \"zfs list -t snapshot -S creation -o name -H -r $TargetDataset |sed -n -e '0,/.*@$SyncSnapshot/s/^.*@$SyncSnapshot//p'\"")
if [ "$?" -ne 0 ]; then
	### check if parent exists
	echo "no snapshot found on the target"
	TargetParentDataset=$(dirname $TargetDataset)
	if [ "$TargetParentDataset" == "/" ] || [ "$TargetParentDataset" == "." ]; then
		errcho "target dataset '$TargetParentDataset' not found."
		exit 1
	fi

	TargetParentSnapshot=$($TargetShell "zfs list -t snapshot -S creation -o name -H -r $TargetParentDataset")
	if [ "$?" -ne 0 ]; then
		errcho "parent of the target dataset does not exist"
		exit 1
	fi

	FullSnapshot=true
fi

LastSourceSnapshot=$($SourceShell "bash -o pipefail -c \"zfs list -t snapshot -S creation -o name -H -r $SourceDataset |sed -n -e '0,/.*@$SyncSnapshot/s/^.*@$SyncSnapshot//p'\"")
if [ "$?" -ne 0 ]; then
	errcho "source dataset '$SourceDataset' not found."
	exit 1
fi

### check Snapshots
if [ "$LastTargetSnapshot" == "" ] && [ "$FullSnapshot" == false ]; then
	echo "FullSnapshot $FullSnapshot"
	echo "$LastTargetSnapshot"
	errcho "target dataset is not empty and snapshots for zdsync are not found"
	exit 1
fi

if [ "$LastSourceSnapshot" == "" ]; then
	LastSourceSnapshot="0"
fi

### sync

DiffTime=$(expr $CurrentTime - $LastSourceSnapshot)
DeltaSnapshotTime=10 # 10 sec for testing

if ((DiffTime > DeltaSnapshotTime)); then
	### create new snapshot on source datset
	LastSourceSnapshot=$($SourceShell "zfs snapshot $SourceDataset@$SyncSnapshot$CurrentTime")
	if [ "$?" -ne 0 ] || [ -n "$LastSourceSnapshot" ]; then
		errcho "could not create snapshot on source dataset"
		exit 1
	fi
	LastSourceSnapshot=$CurrentTime

else
	echo "Snapshot on Target is too new"
	exit 0
fi

if [ "$FullSnapshot" == false ] && (("$LastTargetSnapshot" >= "$LastSourceSnapshot")); then
	errcho "source snapshot must be older than the target one!"
	exit 1
fi

if [ "$FullSnapshot" == true ]; then
	ZFSSend="zfs send $SourceDataset@$SyncSnapshot$LastSourceSnapshot"
else
	ZFSSend="zfs send -i $SourceDataset@$SyncSnapshot$LastTargetSnapshot $SourceDataset@$SyncSnapshot$LastSourceSnapshot"
fi

echo $(bash -o pipefail -c "$SourceShell \"$ZFSSend\" |$TargetShell \"zfs recv $TargetDataset\"")

if [ "$?" -eq 0 ] && [ "$FullSnapshot" == false ] && [ "$KeepSource" == false ]; then
	### Test if newest snapshot is found on the target
	NewTargetSnapshot=$($TargetShell "bash -o pipefail -c \"zfs list -t snapshot -S creation -o name -H -r $TargetDataset |sed -n -e '0,/.*@$SyncSnapshot/s/^.*@$SyncSnapshot//p'\"")
	if [ "$?" -ne 0 ]; then
		errcho "failed to save snapshot on the target"
		exit 1
	fi

	if [ "$NewTargetSnapshot" == "$LastSourceSnapshot" ]; then
		### delete old sync snapshot on source dataset.
		echo "deleting old sync snapshot on source: '$SourceDataset@$SyncSnapshot$LastTargetSnapshot'"
		$($SourceShell "zfs destroy $SourceDataset@$SyncSnapshot$LastTargetSnapshot")


		echo "deleting old sync snapshot on target: '$TargetDataset@$SyncSnapshot$LastTargetSnapshot'"
		$($TargetShell "zfs destroy $TargetDataset@$SyncSnapshot$LastTargetSnapshot")
	fi
fi
