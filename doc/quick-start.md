# Studio quick start

Run inside your Flutter project:

```bash
torchinlane studio
```

Keep the terminal open; Ctrl+C closes Studio. Use **Interface language** in the
header to select **Türkçe** or **English**. Your choice is remembered. It changes
only the panel: source/target locales, store text and unsaved edits are preserved.

1. **Overview:** select the stores you use. Existing files are checked and completed
   steps are marked. Follow the recommended step; skip work already completed.
2. **Setup:** complete only missing settings. Existing valid-format credentials
   do not need re-importing. Check store access separately before uploading.
   Content preparation needs no store key. Tools and signing are needed only for
   uploads/builds; checks do not install anything. Repair is an explicit action.
3. **Texts:** open your source language, write app metadata/release notes and save.
   Reuse common source fields from the other store if appropriate. Populated
   destination fields are preserved; incompatible limits are rejected.
4. **Translation:** add target languages, click **Prepare translation task**, then
   **Copy task**. Paste into Claude Code/Codex in this Flutter project. Once the
   agent finishes, click **Reload and check results**. No translation API key is
   needed; agent subscription/usage limits apply. Repeat for the other store if
   needed. Completed translations can be skipped.
5. **Images:** add ready-made PNG/JPEG assets per locale/device only if needed.
   Existing remote images do not have to be imported again. Image text is not
   translated by this tool.
6. **Upload:** choose the scope (app metadata by default), check the plan, then
   upload. Google notes need the existing build number and track. A new AAB/IPA
   belongs in the separate app build section. Google releases stay drafts;
   Apple review submission is separate.

Advanced API translation, overwrite, remote import/export and build options are
available under expandable sections. Native tool diagnostics retain their
original language. Successful live access checks are remembered for the server
session; changing credentials/app identity invalidates them. Restarting Studio
can require a new access check, but never a new import of an existing valid key.
