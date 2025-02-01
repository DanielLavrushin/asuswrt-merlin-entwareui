/* eslint-disable @typescript-eslint/no-var-requires */
/* eslint-disable no-console */
const ftp = require("basic-ftp");

require("dotenv").config();

async function uploadFiles() {
  const client = new ftp.Client();
  client.ftp.verbose = false;

  try {
    await client.access({
      host: process.env.FTP_ROUTER,
      user: process.env.FTP_USERNAME,
      password: process.env.FTP_PASSWORD,
      port: 21,
      secure: false
    });
    console.log("Ensuring directories exist...");
    await client.ensureDir("/addons/entwareui");
    await client.ensureDir("/scripts");

    await client.uploadFrom("dist/index.asp", "/addons/entwareui/index.asp");
    await client.uploadFrom("dist/app.js", "/addons/entwareui/app.js");
    await client.uploadFrom("dist/entwareui", "/scripts/entwareui");

    await client.send("SITE CHMOD 755 /scripts/entwareui");

    console.log("Files uploaded successfully");
  } catch (err) {
    console.error("Error uploading files:", err);
  } finally {
    client.close();
  }
}

uploadFiles();
