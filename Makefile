# Makefile pour linux-sys-monitor
INSTALL_DIR = /home/maxime/linux-sys-monitor
SYSTEMD_DIR = /etc/systemd/system

install:
	@echo "Installation du service..."
	sudo cp linux-sys-monitor.service $(SYSTEMD_DIR)/
	sudo systemctl daemon-reload
	sudo systemctl enable linux-sys-monitor.service
	sudo systemctl start linux-sys-monitor.service
	@echo "Installation terminée avec succès."

uninstall:
	@echo "Suppression du service..."
	sudo systemctl stop linux-sys-monitor.service
	sudo systemctl disable linux-sys-monitor.service
	sudo rm $(SYSTEMD_DIR)/linux-sys-monitor.service
	sudo systemctl daemon-reload
	@echo "Suppression terminée."

restart:
	sudo systemctl restart linux-sys-monitor.service
	@echo "Service redémarré."
