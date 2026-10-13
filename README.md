# CS528 Homework 4: Web server and forbidden-request tracker on VMs

## Layout

```
service1/
  server.py           web server (GET/POST files, 404, 501, forbidden countries)
  requirements.txt    Python libraries for the server
scripts/
  startup-server.sh   VM startup script for the server VM
```

Service 2 and the one-command deploy script will be added here.

## Project details

| Item | Value |
|---|---|
| Project ID | `project-f131ec20-0df6-4cfa-bf0` |
| Bucket | `cs528-12kfiles-bucket-thomas` |
| Code location in the bucket | `gs://cs528-12kfiles-bucket-thomas/hw4-code/` |
| Server service account | `hw4-sa@project-f131ec20-0df6-4cfa-bf0.iam.gserviceaccount.com` |
| Pub/Sub topic / subscription | `forbidden-requests` / `forbidden-sub` |

## Upload the code to the bucket

The VMs copy their code from the bucket at boot. Run this from the repository folder
whenever the code changes:

```bash
gcloud storage cp -r service1 gs://cs528-12kfiles-bucket-thomas/hw4-code/
```

## Server startup script

`scripts/startup-server.sh` runs as root on every boot. It installs `python3-venv`,
copies `server.py` and `requirements.txt` from the bucket, installs the libraries into
`/opt/hw4/venv`, and runs the server as the systemd service `hw4-server` on port 80.
The service runs as an unprivileged user that may only bind port 80, and restarts
automatically if it crashes.

Useful commands on the server VM:

```bash
sudo journalctl -u google-startup-scripts   # startup script output
sudo systemctl status hw4-server            # is the server running?
sudo journalctl -u hw4-server -f            # server output
```
