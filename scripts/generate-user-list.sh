#!/bin/bash
#
# Generate User List Script
# Creates a markdown/HTML user list for distribution
#

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ARTIFACTS_DIR="$PROJECT_ROOT/artifacts"
CSV_FILE="${CSV_FILE:-$ARTIFACTS_DIR/workshop-users.csv}"
OUTPUT_FORMAT="${1:-markdown}"  # markdown, html, table

# Check if CSV exists
if [ ! -f "$CSV_FILE" ]; then
    echo "Error: User credentials CSV not found: $CSV_FILE"
    echo "Please run the workshop provisioning first."
    exit 1
fi

# Get cluster info
CLUSTER_URL=$(oc whoami --show-server 2>/dev/null || echo "https://your-cluster.example.com:6443")
CONSOLE_URL=$(oc whoami --show-console 2>/dev/null || echo "https://console-openshift-console.apps.your-cluster.example.com")
DEVSPACES_URL=$(oc get route devspaces -n openshift-devspaces -o jsonpath='{.spec.host}' 2>/dev/null || echo "devspaces.apps.your-cluster.example.com")

# Output file
OUTPUT_FILE="$ARTIFACTS_DIR/workshop-user-list.${OUTPUT_FORMAT}"

case "$OUTPUT_FORMAT" in
    markdown|md)
        OUTPUT_FILE="$ARTIFACTS_DIR/workshop-user-list.md"

        cat > "$OUTPUT_FILE" <<EOF
# Workshop User Credentials

**Generated:** $(date)

## Cluster Information

- **OpenShift Console:** $CONSOLE_URL
- **Dev Spaces Dashboard:** https://$DEVSPACES_URL
- **Identity Provider:** workshop_htpasswd

## Login Instructions

1. Navigate to the OpenShift Console: $CONSOLE_URL
2. Click "workshop_htpasswd"
3. Enter your username and password from the table below
4. After login, access Dev Spaces from the application launcher (9 dots icon)

## User Credentials

| Username | Password | Namespace |
|----------|----------|-----------|
EOF

        tail -n +2 "$CSV_FILE" | while IFS=',' read -r username password namespace; do
            echo "| $username | \`$password\` | $namespace |" >> "$OUTPUT_FILE"
        done

        cat >> "$OUTPUT_FILE" <<EOF

## Getting Started

1. Log in to OpenShift Console using your credentials
2. Open the Dev Spaces Dashboard
3. Start your workspace: "spring-to-quarkus-${username}"
4. Wait for the workspace to initialize (2-3 minutes on first start)
5. Follow the workshop guide

## Support

If you encounter issues:
- Check your username/password are correct
- Ensure you selected "workshop_htpasswd" as the login method
- Contact the workshop administrator

---
*Keep this information secure. Do not share your password.*
EOF
        ;;

    html)
        OUTPUT_FILE="$ARTIFACTS_DIR/workshop-user-list.html"

        cat > "$OUTPUT_FILE" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Workshop User Credentials</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 1200px;
            margin: 40px auto;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            background-color: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 {
            color: #ee0000;
            border-bottom: 3px solid #ee0000;
            padding-bottom: 10px;
        }
        h2 {
            color: #333;
            margin-top: 30px;
        }
        .info-box {
            background-color: #f0f0f0;
            padding: 15px;
            border-radius: 5px;
            margin: 20px 0;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
        }
        th {
            background-color: #ee0000;
            color: white;
            padding: 12px;
            text-align: left;
        }
        td {
            padding: 10px;
            border-bottom: 1px solid #ddd;
        }
        tr:hover {
            background-color: #f9f9f9;
        }
        code {
            background-color: #f4f4f4;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: 'Courier New', monospace;
        }
        .warning {
            background-color: #fff3cd;
            border-left: 4px solid #ffc107;
            padding: 15px;
            margin: 20px 0;
        }
        .steps {
            background-color: #e8f4f8;
            border-left: 4px solid #0066cc;
            padding: 15px;
            margin: 20px 0;
        }
        .steps ol {
            margin: 10px 0;
            padding-left: 20px;
        }
        .footer {
            margin-top: 40px;
            padding-top: 20px;
            border-top: 1px solid #ddd;
            font-size: 0.9em;
            color: #666;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Workshop User Credentials</h1>
        <p><strong>Generated:</strong> $(date)</p>

        <h2>Cluster Information</h2>
        <div class="info-box">
            <p><strong>OpenShift Console:</strong> <a href="$CONSOLE_URL" target="_blank">$CONSOLE_URL</a></p>
            <p><strong>Dev Spaces Dashboard:</strong> <a href="https://$DEVSPACES_URL" target="_blank">https://$DEVSPACES_URL</a></p>
            <p><strong>Identity Provider:</strong> workshop_htpasswd</p>
        </div>

        <h2>Login Instructions</h2>
        <div class="steps">
            <ol>
                <li>Navigate to the OpenShift Console</li>
                <li>Click on <strong>"workshop_htpasswd"</strong></li>
                <li>Enter your username and password from the table below</li>
                <li>After login, access Dev Spaces from the application launcher (9 dots icon)</li>
            </ol>
        </div>

        <h2>User Credentials</h2>
        <table>
            <thead>
                <tr>
                    <th>Username</th>
                    <th>Password</th>
                    <th>Namespace</th>
                </tr>
            </thead>
            <tbody>
EOF

        tail -n +2 "$CSV_FILE" | while IFS=',' read -r username password namespace; do
            echo "                <tr>" >> "$OUTPUT_FILE"
            echo "                    <td><strong>$username</strong></td>" >> "$OUTPUT_FILE"
            echo "                    <td><code>$password</code></td>" >> "$OUTPUT_FILE"
            echo "                    <td>$namespace</td>" >> "$OUTPUT_FILE"
            echo "                </tr>" >> "$OUTPUT_FILE"
        done

        cat >> "$OUTPUT_FILE" <<EOF
            </tbody>
        </table>

        <h2>Getting Started</h2>
        <div class="steps">
            <ol>
                <li>Log in to OpenShift Console using your credentials</li>
                <li>Open the Dev Spaces Dashboard</li>
                <li>Start your workspace: <strong>spring-to-quarkus-[your-username]</strong></li>
                <li>Wait for the workspace to initialize (2-3 minutes on first start)</li>
                <li>Follow the workshop guide</li>
            </ol>
        </div>

        <h2>Support</h2>
        <p>If you encounter issues:</p>
        <ul>
            <li>Check your username/password are correct</li>
            <li>Ensure you selected "workshop_htpasswd" as the login method</li>
            <li>Contact the workshop administrator</li>
        </ul>

        <div class="warning">
            <strong>⚠️ Important:</strong> Keep this information secure. Do not share your password with others.
        </div>

        <div class="footer">
            <p>OpenShift Dev Spaces + Developer Lightspeed Workshop</p>
            <p>Spring Boot to Quarkus Migration</p>
        </div>
    </div>
</body>
</html>
EOF
        ;;

    table)
        OUTPUT_FILE="$ARTIFACTS_DIR/workshop-user-list.txt"

        cat > "$OUTPUT_FILE" <<EOF
================================================================================
                    Workshop User Credentials
================================================================================

Generated: $(date)

Cluster Information
-------------------
OpenShift Console:    $CONSOLE_URL
Dev Spaces Dashboard: https://$DEVSPACES_URL
Identity Provider:    workshop_htpasswd

Login Instructions
------------------
1. Navigate to the OpenShift Console
2. Click "workshop_htpasswd"
3. Enter your username and password from the table below
4. Access Dev Spaces from the application launcher (9 dots icon)

User Credentials
----------------
EOF

        printf "%-15s %-25s %-20s\n" "USERNAME" "PASSWORD" "NAMESPACE" >> "$OUTPUT_FILE"
        printf "%-15s %-25s %-20s\n" "===============" "=========================" "====================" >> "$OUTPUT_FILE"

        tail -n +2 "$CSV_FILE" | while IFS=',' read -r username password namespace; do
            printf "%-15s %-25s %-20s\n" "$username" "$password" "$namespace" >> "$OUTPUT_FILE"
        done

        cat >> "$OUTPUT_FILE" <<EOF

================================================================================
Keep this information secure. Do not share your password.
================================================================================
EOF
        ;;

    *)
        echo "Error: Unknown output format: $OUTPUT_FORMAT"
        echo "Usage: $0 [markdown|html|table]"
        exit 1
        ;;
esac

echo "User list generated: $OUTPUT_FILE"
echo ""
echo "You can now distribute this file to workshop participants."

if [ "$OUTPUT_FORMAT" = "html" ]; then
    echo ""
    echo "To view the HTML file, open it in a browser:"
    echo "  open $OUTPUT_FILE"
fi
