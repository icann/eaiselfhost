# Make auxiliary tar file

FILES=makeboxes.py checkdns.py addmbox


eaifiles.tar: ${FILES}
	tar cvf $@ ${FILES}

