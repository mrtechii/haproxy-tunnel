# HAProxy Tunnel Manager CLI

A secure, stable, and high-performance reverse proxy for NAT traversal, written in Bash.
This CLI tool helps you manage HAProxy dynamic port forwarding tunnels on your server.

## Features

-   **Add New Tunnel:** Configure a new backend IP with a list of ports and mode (TCP/HTTP).
-   **Edit Tunnel:** Modify existing tunnel configurations.
-   **Delete Tunnel:** Remove a tunnel.
-   **List Tunnels:** View all configured tunnels.
-   **Manage Default Health Check Port:** Set a global health check port for TCP backends.
-   **Automatic Configuration Application:** Changes are automatically applied and HAProxy service restarted.
-   **HAProxy Service Status:** Check the current status of the HAProxy service.

## How to Install and Run

You can download and install this tool with a single command on your server (Debian or Ubuntu)
```shell
bash <(curl -sL https://raw.githubusercontent.com/mrtechii/haproxy-tunnel/main/haproxy.sh)```


## Support the Project

If you find this tool useful and would like to support its continued development, please consider donating:


**Cryptocurrency Donations:**

-   **USDT (TRC20 - Tron Network):** `TGaUHS8KfhdnJEXZ5so6KwGT9vPTbXHzUm`
-   **USDT (bep20 - BSC Network):** `0x9306e266b152e602ba885547123208fcdae4716e`
-   **TRX (TRC20 - Tron Network):** `TGaUHS8KfhdnJEXZ5so6KwGT9vPTbXHzUm`
