# Make auxiliary tar file

FILES=makeusers.py checkdns.py addmbox


eaifiles.tar: ${FILES}
	tar cvf $@ ${FILES}

