### ZDSync

sync tool between zfs datasets

usage:
```
zdsync.sh [OPTION] SourceDataset TargetDataset

Options:
-s, --sourceShell           specify the source shell to use
-t, --targetShell           specify the target shell to use
-p, --prefix                specify the prefix to use
-k, --keepSource            keep the sync snapshot on the source datset
-c, --timestamp             sets the 'current time' of the script (unix timestamp). Perfect to time large script executions.
```

example:
```bash
zdsync.sh -s "ssh -i /home/sshuser/.ssh/id_rsa root@myserver.example.org" -p my-sync-prefix target_zfs_dataset my/local/zfs-dataset
```
