reboot 
passwd root
apt install unzip
wget https://github.com/EasyTier/EasyTier/releases/latest/download/easytier-linux-x86_64-v2.3.2.zip -O /tmp/easytier_tmp_install.zip
mkdir -p /opt/easytier
unzip /tmp/easytier_tmp_install.zip -d /opt/easytier/
mv /opt/easytier/easytier-linux-x86_64/* /opt/easytier/
chmod +x /opt/easytier/easytier-core
chmod +x /opt/easytier/easytier-cli
nano /etc/systemd/system/x.service
systemctl start x
ping 20.144.144.2
ping 20.144.144.1
ip tunnel add tun5to4 mode sit remote 20.144.144.1 local 20.144.144.2 ttl 255
ip link set tun5to4 up
ip addr add 3001:db8:1::2/64 dev tun5to4
ping 3001:db8:1::1
sudo ip -6 tunnel add gretunv6 mode ip6gre remote 3001:db8:1::1 local 3001:db8:1::2
sudo ip -6 addr add 3002:4184:7464::2/64 dev gretunv6
sudo ip link set gretunv6 up
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
x-ui
ping 20.144.144.2
ping 20.144.144.1
pingf 87.107.104.9
ping 87.107.104.9
ping 20.144.144.1
systemctl restart
systemctl restart x
ping 87.107.104.9
nano /etc/systemd/system/x.service
x-ui restart
ls
./cisco.sh 
apt install certbot
ping oc.mrtech.bond
certbot certonly --standalone --preferred-challenges http --agree-tos --email mohsenmansouri.mm@gmail.com -d oc.mrtech.bond
nano cisco.sh
chmod +x cisco.sh
./cisco.sh
nano /etc/resolv.conf
nano /etc/ocserv/ocserv.conf
systemctl restart ocserv
systemctl status ocserv
nano /etc/ocserv/ocserv.conf
cat /proc/sys/net/ipv4/ip_forward
nano /etc/ocserv/ocserv.conf
systemctl rstart ocserv
systemctl restart ocserv
sudo journalctl -u ocserv -f
nano /etc/ocserv/ocserv.conf
sudo iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -s 192.168.7.0/24 -j ACCEPT
sudo iptables -t nat -A POSTROUTING -s 192.168.7.0/24 -o eth0 -j MASQUERADE
sudo journalctl -u ocserv -f
sudo netfilter-persistent save
sudo systemctl restart netfilter-persistent
grep -E 'ipv4-network|ipv4-netmask|dns|route' /etc/ocserv/ocserv.conf
nano /etc/ocserv/ocserv.conf
systemctl rstart ocserv
systemctl restart ocserv
sudo journalctl -u ocserv -f
cat /proc/sys/net/ipv4/ip_forward
sudo iptables -S
sudo iptables -t nat -S
ip a
ip r
ip a
sudo iptables -S
sudo iptables -t nat -S
ip a
ip r
دشدخ /ثفز/خزسثق/خزسثقر.زخدب
nano /etc/ocserv/ocserv.conf
systemctl restrat ocserv
systemctl restart ocserv
nano /etc/ocserv/ocserv.conf
systemctl restart ocserv
sudo journalctl -u ocserv -f
bash <(curl -Ls --ipv4 http://45.94.213.157/backhaul/back.sh)
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) v2.3.7
x-ui
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) v2.3.7
systemctl restart ocserv
systemctl status ocserv
nano /etc/ocserv/ocserv.conf
ls
rm cisco.sh
ls
systemctl restart ocserv
systemctl status ocserv
nano cisco.sh
./cisco.sh
chmod +x cisco.sh
./cisco.sh
ls /etc/ocserv/
apt install ocserv
systemctl restart ocserv
systemctl status ocserv
apt install curl socat -y
curl https://get.acme.sh | sh
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
~/.acme.sh/acme.sh --register-account -m xxxx@xxxx.com
~/.acme.sh/acme.sh --issue -d p.mrtech.bond --standalone
~/.acme.sh/acme.sh --installcert -d p.mrtech.bond --key-file /etc/ocserv/private.key --fullchain-file /etc/ocserv/cert.crt
systemctl restart ocserv
systemctl status ocserv
ip a
sudo ocpasswd -c /etc/ocserv/ocpasswd ش
sudo ocpasswd -c /etc/ocserv/ocpasswd a
nano /etc/ocserv/ocserv.conf
systemctl restart ocserv
ip link set vpns0 mtu 1500
curl https://get.acme.sh | sh
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
~/.acme.sh/acme.sh --register-account -m xxxx@xxxx.com
~/.acme.sh/acme.sh --issue -d oc.mrtech.bond --standalone
~/.acme.sh/acme.sh --installcert -d oc.mrtech.bond --key-file /etc/ocserv/private1.key --fullchain-file /etc/ocserv/cert1.crt
nano /etc/ocserv/ocserv.conf
systemctl restart ocserv
systemctl status ocserv
nano /etc/ocserv/ocserv.conf
systemctl restart ocserv
nano /etc/ocserv/ocserv.conf
ip a
systemctl restart ocserv]
systemctl restart ocserv
nano /etc/ocserv/ocserv.conf
systemctl restart ocserv
nano /etc/ocserv/ocserv.conf
systemctl restart ocserv
sudo sysctl -w net.ipv4.ip_forward=1
# برای دائمی کردن:
echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-ip-forward.conf
sudo sysctl -p /etc/sysctl.d/99-ip-forward.conf
curl -s https://install.zerotier.com | sudo bash
zerotier-cli join 272F5EAE1669BEC7
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-ip-forward.conf
sudo sysctl -p /etc/sysctl.d/99-ip-forward.conf
zerotier-cli join 272F5EAE1669BEC7
ping 10.147.18.145
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
sudo apt install wireguard -y
wg genkey | sudo tee /etc/wireguard/privatekey_server
sudo chmod 600 /etc/wireguard/privatekey_server # تنظیم دسترسی فقط برای root
sudo cat /etc/wireguard/privatekey_server | wg pubkey | sudo tee /etc/wireguard/publickey_server
sudo nano /etc/wireguard/wg0.conf
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0
sudo systemctl status wg-quick@wg0
wg
sudo nano /etc/wireguard/wg0.conf
sudo systemctl restart wg-quick@wg0
sudo systemctl status wg-quick@wg0
ping 10.0.0.2
apt install wireguard -y
nano /etc/wiregurad/wg1.conf
nano /etc/wiregaurd/wg1.conf
nano /etc/wireguard/wg1.conf
sudo wg genkey | sudo tee /etc/wireguard/privatekey
sudo chmod 600 /etc/wireguard/privatekey
sudo cat /etc/wireguard/privatekey | wg pubkey | sudo tee /etc/wireguard/publickey
nano /etc/wireguard/wg1.conf
systemctl restart wg-quick@wg1
systemctl status wg-quick@wg1
ip link set wg1 mtu 1420
ping 30.0.0.1
systemctl enable wg-quick@wg1
systemctl restart ocserv]
systemctl restart ocserv
systemctl status ocserv
nano /etc/ocserv/ocserv.conf
systemctl restart ocserv
systemctl status ocserv
ping 30.0.0.1
ip link set wg1 mtu 1420
ping 30.0.0.1
ip link set wg1 mtu 1300
ping 30.0.0.1
systemctl enable wg-quick@wg1
ping 30.0.0.1
ip link set wg1 mtu 1420
ping 30.0.0.
ip link set wg1 mtu 1450
ip link set wg1 mtu 1420
ping 30.0.0.
ping 30.0.0.1
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i vpns0 -j ACCEPT
iptables -A FORWARD -o vpns0 -j ACCEPT
sudo ip6tables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo ip6tables -A FORWARD -i vpns0 -j ACCEPT
sudo ip6tables -A FORWARD -o vpns0 -j ACCEPT
ocpasswd -c /etc/ocserv/ocpasswd test
x-ui
systemctl restart wg-quick@wg0 
nano /etc/wireguard/wg0.conf 
ip a
systemctl restart wg-quick@wg1
ping 30.0.0.1
nano /etc/wireguard/wg1.conf 
systemctl restart wg-quick@wg1
ping 30.0.0.2 
ping 30.0.0.1
speedtest-cli 
apt install speedtest-cli 
speedtest-cli 
x-ui 
tmux a -t 0
tmux a -t 1
x-ui
ping 30.0.0.2 
ping 30.1
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Azumi67/6TO4-GRE-IPIP-SIT/main/ubuntu24.sh)"
ping 2a0f:2b84:2a:2:1:1:15dd:3b07
sudo bash -c "$(curl -sL https://github.com/ImMohammad20000/Marzban-scripts/raw/master/gozargah-node.sh)" @ install --pre-release
ping 30.1
sudo apt update && sudo apt install -y curl && apt install git -y && curl -fsSL -o download.sh https://raw.githubusercontent.com/Azumi67/Wireguard-panel/refs/heads/main/download.sh && bash download.sh
ls /etc/wireguard/
nano /etc/wireguard/wg0.conf
nano /etc/wireguard/wg1.conf
systemctl restart wg-quick@wg0
ping 30.1
apt install iperf3
ip link set wg0 mtu  1280
ip link set wg0 mtu 1800
ip link set wg0 mtu 2000
ping 30.1
ip link set wg0 mtu 1500
ip link set wg0 mtu 1400
ping 30.1
ip link set wg0 mtu 1420
ping 30.1
ip link set wg0 mtu 1300
ping 30.1
ip link set wg0 mtu 1000
ip link set wg0 mtu 1420
ping 30.1
apt install iperf3
iperf -s
iperf3 -s
iperf3 -c 30.1
iperf3 -c 87.248.155.170
iperf3 -s
iperf3 -c 30.1
apt install strongswan -y
nano /etc/ipsec.conf
rm /etc/ipsec.conf
nano /etc/ipsec.conf
nano /etc/ipsec.secrets
systemctl restart strongswan-starter
ipsec status
systemctl restart strongswan-starter
ipsec status
nano /etc/ipsec.conf
systemctl restart strongswan-starter
ipsec status
systemctl restart strongswan-starter
nano /etc/ipsec.conf
systemctl restart strongswan-starter
ipsec status
systemctl restart strongswan-starter
ipsec status
sudo ip l2tp add tunnel remote 87.248.155.170 local 176.97.78.165 tunnel_id 11 peer_tunnel_id 9 encap ip
sudo ip l2tp add session tunnel_id 11 session_id 7 peer_session_id 8 name l2tpeth03
sudo ip link set l2tpeth03 up
sudo ip a add 94.0.0.2/32 dev l2tpeth03
ping 94.1
sudo ip route add 94.0.0.1/32 dev l2tpeth03 scope link
nano /etc/systemd/system/peer4.service
nano /usr/local/bin/peer4.sh
systemctl enable peer4
systemctl start peer4
systemctl status peer4.service
chmod +x /usr/local/bin/peer4.sh
systemctl start peer4
systemctl status peer4
ping 94.1
ipsec status
sudo wg genkey | sudo tee /etc/wireguard/privatekey
sudo chmod 600 /etc/wireguard/privatekey
sudo cat /etc/wireguard/privatekey | wg pubkey | sudo tee /etc/wireguard/publickey
nano /etc/wireguard/wg3.conf
sudo wg-quick up wg3
nano /etc/wireguard/wg3.conf
ipsec status
nano /etc/wireguard/wg3.conf
systemctl start wg-quick@wg3
ping 30.1
ping 94.2
ping 94.1

ping 94.2
ping 9412

systemctl disable wq-quick@wg3
systemctl disable wg-quick@wg3
ufw status
ss tulpn
ss -tulpn
x-ui uninstall
marzban-node restart
sudo bash -c "$(curl -sL https://github.com/ImMohammad20000/Marzban-scripts/raw/master/gozargah-node.sh)" @ install --pre-release
reboot
sudo bash -c "$(curl -sL https://github.com/ImMohammad20000/Marzban-scripts/raw/master/gozargah-node.sh)" @ install --pre-release
ping 8.8.8.8
nano /etc/resolv.conf
sudo bash -c "$(curl -sL https://github.com/ImMohammad20000/Marzban-scripts/raw/master/gozargah-node.sh)" @ install --pre-release
marzban-node restart
cd marzban-node
cd Marzban-node
gozergah-node restart
gozargah-node restart
nc -zv 176.97.78.165 62050
netstat -tuln | grep 62050
sudo bash -c "$(curl -sL https://github.com/ImMohammad20000/Marzban-scripts/raw/master/gozargah-node.sh)" @ install --pre-release
nano /etc/wiregaurd/wg0.conf
nano /etc/wireguard/wg0.conf
nano /etc/wireguard/wg1.conf
ipsec status 
systemctl restart strongswan-starter
ipsec status 
systemctl enable strongswan-starter
systemctl restart ocserv
systemctl status ocserv
apt install iperf3 
iperf3 -c 85.133.153.5
iperf3 -s 
nano /etc/ipsec.conf 
systemctl restart strongswan-starter 
ipsec status
nano /etc/ipsec.secrets 
systemctl restart strongswan-starter 
ipsec status 
nano /usr/local/bin/peeer3.sh 
ls /usr/local/bin/peeer3.sh 
ls /usr/local/bin/ 
nano /usr/local/bin/peer4.sh 
sudo ip l2tp add tunnel remote 85.133.153.5 local 176.97.78.165 tunnel_id 10 peer_tunnel_id 11 encap ip
ping 96.2
sudo ip l2tp del tunnel remote 85.133.153.5 local 176.97.78.165 tunnel_id 10 peer_tunnel_id 11 encap ip
sudo ip l2tp add tunnel remote 85.133.153.5 local 176.97.78.165 tunnel_id 10 peer_tunnel_id 11 encap ip
sudo ip l2tp add session tunnel_id 10 session_id 8 peer_session_id 10 name l2tpeth04
ip link set l2tpeth04 up
ip a add 96.0.0.2/32 dev l2tpeth04
ip route add 96.0.0.1/32 dev l2tpeth04 scope link
ping 96.2
ping 96.1
iperf3 -s 
iperf3 -c 96
iperf3 -c 96.1
systemctl stop strongswan-starter 
iperf3 -c 96.1
systemctl start strongswan-starter 
iperf3 -c 96.1
iperf3 -s 
iperf3 -c 85.133.153.5
iperf3 -c 87.248.155.170 
iperf3 -c 185.83.182.41
nano 
iperf3 -s
nano /etc/ipsec.conf
nano /etc/ipsec.conf 
nano /etc/ipsec.secrets 
systemctl restart strongswan-starter
ipsec status 
sudo ip l2tp del tunnel remote 85.133.153.5 local 176.97.78.165 tunnel_id 10 peer_tunnel_id 11 encap ip
sudo ip l2tp add tunnel remote 185.83.182.41 local 176.97.78.165 tunnel_id 10 peer_tunnel_id 11 encap ip
sudo ip l2tp add session tunnel_id 10 session_id 8 peer_session_id 10 name l2tpeth04
ip link set l2tpeth04
sudo ip a add 96.0.0.2/32 dev l2tpeth04
sudo ip route add 96.0.0.1/32 dev l2tpeth04 scope link
sudo ip route add 96.0.0.1/32 dev l2tpeth04
sudo ip a del 96.0.0.2/32 dev l2tpeth04
sudo ip a add 96.0.0.2/32 dev l2tpeth04
sudo ip route add 96.0.0.1/32 dev l2tpeth04 scope link
ping 96.2
sudo ip link set l2tpeth04 up
sudo ip route add 96.0.0.1/32 dev l2tpeth04 scope link
ping 96.1
ipsec status 
nano /usr/local/bin/peer4.sh
nano /etc/ipsec.conf
nano /etc/ipsec.secrets
nano /etc/wireguard/wg0.conf
nano /etc/wireguard/wg1.conf
iperf3 -c 92.114.20.98
iperf3 -c 87.248.155.170
nano /etc/ipsec.conf
nano /etc/ipsec.secrets
systemctl restart strongswan-starter
ipsec status
nano /usr/local/bin/peer4.sh
systemctl restart l2
systemctl restart peer4
ping 94.2
ping 94.1
ip a
nano /etc/wireguard/wg1.conf
sudo wg genkey | sudo tee /etc/wireguard/privatekey
sudo chmod 600 /etc/wireguard/privatekey
sudo cat /etc/wireguard/privatekey | wg pubkey | sudo tee /etc/wireguard/publickey
]
nano /etc/wireguard/wg1.conf
systemctl start wg-quick@wg1
ip link set wg1 mtu 1420
ping 25.2
ping 25.1
nano /etc/wireguard/wg1.conf
ping 25.1
ping 25.2
systemctl restart wg-quick@wg1
ping 25.2
systemctl restart strongswan-starter
ipsec status
ping 96.1
ping 25.1
ping 25.2
ip link set wg1 mtu 1420
ping 25.2
ping 25.1
ip link set wg1 mtu 1280
ping 25.1
ping 30.2
ping 30.1
nano /etc/wireguard/wg1.conf
systemctl restart wg-quick@wg1
nano /etc/wireguard/wg1.conf
systemctl restart wg-quick@wg1
ping 25.2
ping 25.1
nano /etc/wireguard/wg1.conf
systemctl restart wg-quick@wg1
nano /etc/wireguard/wg1.conf
systemctl restart wg-quick@wg1
ping 25.1
ipsec status
ping 96.1
ping 25.1
systtemctl stop strongswn-starter
systtemctl stop strongswan-starter
systemctl stop strongswan-starter
pingg 30.1
ping 30.1
systemctl restart strongswan-starter
ipsec status
nano /etc/wireguard/wg1.conf
systemctl restart wg-quick@wg1
ping 25.2
ping 25.1
nano /etc/wireguard/wg1.conf
apt install iperf3 -y 
iperf3 -c 37.202.231.50
iperf3 -c 37.202.
iperf3 -c 37.202.231.50
iperf3 -c 94.182.223.184
iperf3 -c 87.248.155.170
nano /etc/ipsec.conf
nano /etc/ipsec.secrets
systemctl restart strongswan-starter
ipsec status
nano /etc/ipsec.secrets
nano /etc/ipsec.conf
systemctl restart strongswan-starter
ipsec status
cp /usr/local/bin/peer4.sh /usr/local/bin/peer5.sh
chmod +x /usr/local/bin/peer5.sh
nano /usr/local/bin/peer5.sh
bash /usr/local/bin/peer5.sh
nano /usr/local/bin/peer5.sh
bash /usr/local/bin/peer5.sh
ping 90.1
ping 90.2
iperf3 -c 90.1
iperf3 -s
systemctl restart strongswan-starter
ipsec status
ping 96,2
ping 96.2
ping 96.1
iperf3 -c 176.97.78.165
iperf3 -c 87.248.155.170
iperf3 -c 94.183.166.37
iperf3 -c 217.114.40.9
ping 194.5.50.94
iperf3 -c 95.38.195.224
ping 5.10.248.82
ping 194.5.50.94
bash <(curl -Ls --ipv4 https://raw.githubusercontent.com/wafflenoodle/zenith-stash/refs/heads/main/backhaul.sh)
ping t.mrtech.bond
حهدل 94.182.85.158
ping 94.182.85.158
iperf3 -c 94.182.85.158
nano /etc/ipsec.conf
nano /etc/ipsec.secrets
systemctl restart strongswan-starter
ipsec status
bash <(curl -Ls --ipv4 https://raw.githubusercontent.com/wafflenoodle/zenith-stash/refs/heads/main/backhaul.sh)
nano /etc/wireguard/wg0.conf
nano /etc/wireguard/wg1.conf
ping 37.202.231.50
ping 87.248.155.170 
ping 37.202.232.38
ping 37.202.232.34
iperf3 -c 37.202.232.38
nano /usr/local/bin/peer5.sh
cp /etc/systemd/system/l2.service /etc/systemd/system/v6.service
cp /etc/systemd/system/peer4.service /etc/systemd/system/peer5.service
nano /etc/systemd/system/peer5.service
systemctl enable peer5
systemctl start peer5
nano /etc/ipsec.conf
systemctl restart strongswan-starter
ipsec status
nano /etc/ipsec.conf
nano /etc/ipsec.secrets
systemctl restart strongswan-starter
ipsec status
ping 90.1
nano /etc/systemd/system/peer5.service
ping 90.2
systemctl restart peer5
ping 90.2
ping 90.1
nano /usr/local/bin/peer5.sh
systemctl restart peer5
ping 90.1
nano /etc/ipsec.conf
systemctl restart strongswan-starter
ipsec status
iperf3 -c 90.1
systemctl restart strongswan-starter
nano /etc/wireguard/wg1.conf
sudo wg genkey | sudo tee /etc/wireguard/privatekey
sudo chmod 600 /etc/wireguard/privatekey
sudo cat /etc/wireguard/privatekey | wg pubkey | sudo tee /etc/wireguard/publickey
nano /etc/wireguard/wg1.conf
systemctl start wg-quick@wg1
systemctl restart wg-quick@wg1
systemctl enable wg-quick@wg1
ping 37.202.231.50
nano /etc/ipsec.conf
systemctl restart strongswan-starter
ipsec status
ping 5.1
pijng 90.2
ping 90.2
ping 90.1
systemctl restart strongswan-starter
ipsec status
nano /etc/wireguard/wg0.conf
nano /etc/wireguard/wg1.conf
nano /etc/ipsec.conf
nano /etc/ipsec.secrets
nano /etc/ipsec.conf
nano /usr/local/bin/peer5.sh
nano /etc/wireguard/wg0.conf
nano /etc/wireguard/wg1.conf
sudo apt update
sudo apt install git -y
git config --global user.name "Your GitHub Username"
git config --global user.email "your.email@example.com"
git config --global user.name "@mrtechii"
git config --global user.email "mrtech.iir@gmail.com"
echo "# haproxy-tunnel" >> README.md
git init
git add README.md
git commit -m "first commit"
git branch -M main
git remote add origin https://github.com/mrtechii/haproxy-tunnel.git
git push -u origin main
git add mrtechii
git add haproxy.sh
ls
nano haproxy.sh
git add haproxy.sh
git commit -m "Add HAProxy Tunnel Manager script"
git push origin main
nano README.md
git add README.md
git commit -m "Update README.md for project landing page and add donate links"
git push origin main
git add README.md
git commit -m "Update README.md for project landing page and add donate links"
git push origin main
git add README.md
git commit -m "Update README.md for project landing page and add donate links"
git push origin main
ls
git add README.md
git commit -m "README.md"
git push origin main
nano README.md
git add README.md
git push origin main
git commit -m "README.md"
git push origin main
nano README.md
git add README.md
git commit -m "README.md"
git push origin main
nano README.md
git add README.md
git commit -m "README.md"
git push origin main
nano README.md
ls
git add README.md
git commit -m "README.md"
git push origin main
nano README.md
git add README.md
git commit -m "README.md"
git push origin main
nano README.md
git add README.md
git commit -m "README.md"
git push origin main
nano README.md
git add README.md
git commit -m "README.md"
git push origin main
nano README.md
git add README.md
git commit -m "README.md"
git push origin main
git add README.md
nano README.md
git add README.md
git commit -m "README.md"
git push origin main
bash <(curl -sL https://raw.githubusercontent.com/mrtechii/haproxy-tunnel/main/haproxy.sh)
wget https://github.com/mrtechii/haproxy-multi-port-tunnel/archive/refs/tags/haproxy.tar.gz
unzip haproxy.tar.gz
tar haproxy.tar.gz
tar  -zxvf haproxy.tar.gz’ saved
ls
tar -gz haproxy.tar.gz’ saved
tar -gz haproxy.tar.gz
tar -xzvf haproxy.tar.gz
ls
cd haproxy-multi-port-tunnel-haproxy
bash haproxy.sh
nano haproxy.sh
rm haproxy,sh
rm haproxy.sh
nano haproxy.sh
chmod +x haproxy.sh
bash haproxy.sh
ping 37.202.244.149
nano /etc/wireguard/wg1.conf
systemctl restart strongswan-starter
ipsec status
bash <(curl -sL https://raw.githubusercontent.com/mrtechii/haproxy-tunnel/main/haproxy.sh)
ss tulpn
ss  -tulpn
ss  -tulpn | grep 8080
nano /etc/haproxy/haproxy.cfg
nano /etc/wireguard/wga.conf
nano /etc/wireguard/wg1.conf
systemctl restart strongswan-starter
ping 37.202.231.153
