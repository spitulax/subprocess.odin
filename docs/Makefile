.PHONY: build mkdir clean serve

SITE_DIR := site

build: subprocess.odin-doc mkdir
	cd $(SITE_DIR) && odin-doc ../subprocess.odin-doc ../odin-doc-config.json

serve: build
	cd $(SITE_DIR) && python3 -m http.server 10101

subprocess.odin-doc:
	odin doc all.odin -file -all-packages -doc-format -out:subprocess.odin-doc

clean:
	rm subprocess.odin-doc
	rm -r $(SITE_DIR)/*

mkdir:
ifeq ($(wildcard $(SITE_DIR)/.),)
	mkdir -p $(SITE_DIR)
endif
