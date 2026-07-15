# Fake BL Manager - Web UI

## Webview Files

These files provide the web-based user interface for Fake BL Manager.

### Files:

- **index.html** - Main dashboard showing status
- **install.html** - Installation interface
- **downgrade.html** - ABL downgrade control
- **rollback.html** - Rollback version checker
- **backup.html** - Backup/restore interface
- **log.html** - Real-time log viewer
- **style.css** - Styling
- **app.js** - Application logic

### How to use:

1. Open webview in browser: `http://localhost:8080`
2. Or use in any web browser on the device

### API Endpoints:

- `/api/status` - Get current status
- `/api/install` - Start installation
- `/api/rollback` - Check rollback version
- `/api/backup` - Create backup
- `/api/log` - Get log entries
