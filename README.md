# BetterGPG

A macOS app for encrypting files to people and groups, then viewing or editing them without leaving an unlocked copy behind.

Drop a file on the window, double-click a `.gpg` file, or right-click it in Finder.

## What it does

- **Keys.** Paste a public key, drop a `.asc` file, or fetch one by email or fingerprint from keys.openpgp.org.
- **Groups.** Bundle people together and encrypt for the whole group.
- **Encrypt.** Drop a normal file and pick a group or individual people. Folders are zipped first. Originals can be overwritten and deleted after a successful encrypt.
- **View and edit.** Drop or double-click an encrypted file to open it in BetterGPG's own window. Text is editable, and PDFs, images, and anything Quick Look understands can be viewed. Closing the window saves any changes back to the encrypted file and wipes the unlocked copy.
- **Notes vault.** Choose a folder in the sidebar or in Settings. New plain text and Markdown notes are encrypted to your key and listed by name. Opening one decrypts it into memory. Markdown can render beside the source and updates as you type. Locking the note, leaving it, or quitting encrypts your changes and clears the unlocked text.
- **Open in another app.** You can also unlock a file for another app, such as Word or Preview. BetterGPG locks it again when that app closes the file or when a safety timer elapses.
- **Finder.** Right-click an encrypted file for **View in BetterGPG** or **Open in Default App with BetterGPG**. Right-click any other file for **Encrypt with BetterGPG…**, or a folder background to encrypt that folder. The same actions are under Finder's Services menu.

## The built-in viewer

- **Memory first.** Files under the memory limit (256 MB by default, set in Settings) are decrypted straight from GPG into locked memory and never touch a disk. Text, PDFs, and common images open this way.
- **Private temp space otherwise.** Larger files, and types only Quick Look can show, are written to the memory disk when it has room. If it doesn't, they go to a private temporary folder (mode 0700, excluded from backups and Spotlight).
- **Saving.** ⌘S, or closing the window, encrypts the edit for the file's original recipients and swaps it in atomically. If the save fails, the window stays open with your changes and offers Try Again or Discard.
- **Locks itself.** Viewers close when the safety timer elapses, when the Mac sleeps or the screen locks (can be turned off), and when you quit. **Lock Everything** (⇧⌘L) closes them all at once.
- **Hidden from capture.** By default, viewer windows are excluded from screenshots and screen sharing.

## Opening in another app

Opening in another app starts a session:

- **Memory disk (default).** The unlocked copy lives on a RAM volume named `BetterGPGMemory`. Ejecting that volume drops the bytes from memory.
- **Private temporary folder.** Use this when the file is larger than the memory disk. The copy is excluded from Time Machine backups and removed with a shred when the session locks.
- **Save changes.** When the session locks, BetterGPG encrypts the edited file back over the original for the same recipients, then shreds the unlocked copy. If that encrypt fails, the unlocked copy is kept.
- **Discard changes.** The unlocked copy is shredded and the original encrypted file is left as it was.
- **When closed.** After the other app closes the file, BetterGPG waits a few seconds, then locks it.
- **Safety timer.** If the timer elapses while the file is still open, the session is marked overdue and locks once the file is closed.
- **Quit.** Quitting with unlocked files asks to lock them first. The Dock badge and menu-bar lock show how many copies are still unlocked.

## Cleanup after crashes

Every unlocked copy, from either the viewer or another app, lives in its own folder on the memory disk or in the private temporary folder. BetterGPG records each folder in `~/Library/Application Support/BetterGPG/plaintext-journal.json` before any plaintext is written.

A cleanup pass runs at launch, every five minutes, at quit, and on demand from Settings. It shreds any folder that no open window or session owns, so a crash or force-quit can't leave plaintext behind for long. A leftover copy that was edited is first encrypted back as `name (recovered).ext.gpg` next to the original, so edits aren't lost. If that fails, the copy is kept for up to 24 hours while cleanup keeps retrying. The memory disk is ejected once nothing is using it.

## Limits

- Shredding overwrites a file with random data and then deletes it. On APFS, and on SSDs in general, that can't promise the previous blocks are gone. The memory disk and in-memory viewer are the stronger options.
- In-memory buffers are locked and zeroed on close. PDFKit, AppKit, and Swift strings keep their own copies, which can't be wiped explicitly and are freed only when the window closes.
- Printing, copying, dragging out, or exporting from a viewer puts the content outside BetterGPG's control.
- Some capture tools ignore the window setting that hides viewers from screenshots.
- Passphrases stay in GPG's pinentry. BetterGPG never reads them.

## Requirements

- macOS 14 or later
- GPG (`brew install gnupg pinentry-mac` or [GPG Suite](https://gpgtools.org))

## Build

```bash
brew install xcodegen
xcodegen generate
open BetterGPG.xcodeproj
```

Or:

```bash
make dev
make run
```

`make install` copies a release build to `/Applications` and refreshes Finder services.

## Finder setup

On first launch, enable **BetterGPGFinderExtension** from the banner or from Settings. If the Services menu items do not appear, run:

```bash
/System/Library/CoreServices/pbs -update
```

The app is not sandboxed, so it can run `gpg` and read files you choose. It is meant for direct distribution, not the App Store. Groups and settings live in `~/Library/Application Support/BetterGPG/` and UserDefaults.
