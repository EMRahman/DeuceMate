# Match archive transfer to a new iPhone

**Deferred feature idea.** A transfer copy should be available on the replacement
iPhone after the original installation is gone.

Today the user can export a full-fidelity archive from **Settings → Backup &
Transfer → Export Match Archive**, choose **iCloud Drive** in Files, and confirm
the save. Once it syncs, they can open **Import Match Archive** on the new iPhone
and select that file from the same Apple Account’s iCloud Drive.

The prototype added **On My iPhone → DeuceMate → Exports** as a convenient place
to save local copies. Deleting DeuceMate removes its app-owned folder, and the
folder lives on the original iPhone. That makes it useful for recovering a local
archive while the app remains installed. For a phone transfer, the user would
still have to move the file out of that folder. [Closed prototype PR #242](https://github.com/EMRahman/DeuceMate/pull/242)

If revisited, make the existing iCloud Drive export and import steps easier to
find and explain how to check that the archive is available before erasing the
old phone. Keep the HealthKit disclosure and separate private-notes opt-in for
each manual export. App-managed iCloud backups use a Health-stripped snapshot.
[Health data flow](../architecture/health-data-flow.md)
