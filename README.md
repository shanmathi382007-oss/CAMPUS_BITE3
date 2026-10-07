# CampusBite (PostgreSQL version)
1. In pgAdmin: right-click Databases > Create > Database > name it `campusbite`.
2. Right-click `campusbite` > Query Tool > open schema.sql > press F5 (Run).
3. Set the `PGPASSWORD` environment variable to your PostgreSQL password; do not put credentials in source code.
4. Terminal: `npm install` then `npm start`
5. Open http://localhost:3000
Demo: student@college.com / student123 | admin@college.com / admin123 (Admin link)

## Install as a phone app (PWA)
- Same machine: open http://localhost:3000 in Chrome/Edge and click the "Install app" button (or the install icon in the address bar).
- On your phone (same Wi-Fi): open http://<your-PC-IP>:3000. Browsers only allow installing over HTTPS (or localhost), so for a real install deploy to an HTTPS host (Render, Railway, Fly.io) with a hosted Postgres and set PGPASSWORD / JWT_SECRET. Use `ngrok http 3000` for a quick HTTPS test.
- Android: menu > Install app. iPhone (Safari): Share > Add to Home Screen.
