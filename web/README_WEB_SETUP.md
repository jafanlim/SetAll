# Web setup (one-time)

For the app to work in the browser, SQLite needs WASM binaries. Run once in the project root:

```bash
dart run sqflite_common_ffi_web:setup
```

This adds `sqflite_sw.js` and `sqlite3.wasm` to the `web/` folder. Then run:

```bash
flutter run -d chrome
```

If you see a white screen, open Chrome DevTools (F12) → Console and check for red errors; that will show the exact failure.
