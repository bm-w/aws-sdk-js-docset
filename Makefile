FILE := $(dir $(lastword $(MAKEFILE_LIST)))
DIR := $(FILE:/=)
SRC_DIR := $(DIR)/src

NAME := AWSSDKNodeJS
PACKAGE_NAME := $(NAME).docset
PACKAGE_DIR := $(DIR)/$(PACKAGE_NAME)
CONTENTS_DIR := $(PACKAGE_DIR)/Contents
RESOURCES_DIR := $(CONTENTS_DIR)/Resources
DOCUMENTS_DIR = $(RESOURCES_DIR)/Documents

PREFIX ?= $(HOME)/Library/Application Support/Dash/DocSets


.PHONY: build build-start install clean

.DEPENDENCIES :=\
	$(PACKAGE_DIR)/icon.png \
	$(CONTENTS_DIR)/Info.plist\
	$(DOCUMENTS_DIR)/DynamoDB.html\
	$(RESOURCES_DIR)/docSet.dsidx

build-start:
	@echo "Generating AWS SDK for node..."

build: build-start $(.DEPENDENCIES)
	@echo "Generated AWS SDK for Node.js docset:\n  $(PACKAGE_DIR)"

install: build
	@test -d "$(PREFIX)" &&\
		mkdir -p "$(PREFIX)/$(NAME)" &&\
		cp -r $(PACKAGE_DIR) "$(PREFIX)/$(NAME)/" &&\
		echo "Installed docset at path:\n  $(PREFIX)/$(NAME)"

clean:
	@rm -rf $(PACKAGE_DIR)

# --

$(PACKAGE_DIR):
	@mkdir -p $(PACKAGE_DIR)

$(CONTENTS_DIR): | $(PACKAGE_DIR)
	@mkdir -p $(CONTENTS_DIR)

$(RESOURCES_DIR): | $(CONTENTS_DIR)
	@mkdir -p $(RESOURCES_DIR)

$(DOCUMENTS_DIR): | $(RESOURCES_DIR)
	@mkdir -p $(DOCUMENTS_DIR)


# --

$(PACKAGE_DIR)/icon.png: $(SRC_DIR)/icon.png $(SRC_DIR)/icon@2x.png  | $(PACKAGE_DIR)
	@tiffutil -cathidpicheck $(SRC_DIR)/icon.png $(SRC_DIR)/icon@2x.png -out $(PACKAGE_DIR)/icon.png 2>/dev/null &&\
	 echo "Generated multi-resolution TIFF icon:\n  $(PACKAGE_DIR)/icon.png"

# --

DASH_PLIST_URL := http://kapeli.com/dash_resources/Info.plist

$(CONTENTS_DIR)/Info.plist: | $(CONTENTS_DIR)
	@curl -s $(DASH_PLIST_URL) |\
		perl -0pe 's/(\t<key>CFBundleIdentifier<\/key>\n\t<string>)jQuery(<\/string>)/\1aws-sdk\2/' |\
		perl -0pe 's/(\t<key>CFBundleName<\/key>\n\t<string>)jQuery(<\/string>)/\1AWS SDK for Node.js\2/' |\
		perl -0pe 's/(\t<key>DocSetPlatformFamily<\/key>\n\t<string>)jQuery(<\/string>)/\1nodejs\2/' |\
		perl -0pe 's/(<\/dict>\n<\/plist>)/\t<key>dashIndexFilePath<\/key>\n\t<string>DynamoDB.html<\/string>\n\1/' \
			> $(CONTENTS_DIR)/Info.plist &&\
		echo "Downloaded and populated property list file:\n  $(CONTENTS_DIR)/Info.plist"

# --

$(DOCUMENTS_DIR)/*.css: | $(DOCUMENTS_DIR)
	@cd $(DOCUMENTS_DIR) && for file in style.css common.css; do \
		curl -sO $(DDB_CSS_BASEURL)/$$file &&\
		echo "Downloaded documentation CSS:\n  $(DOCUMENTS_DIR)/$$file"; \
	done

DDB_20111205_URL := http://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/DynamoDB.html
DDB_CSS_BASEURL := http://docs.aws.amazon.com/AWSJavaScriptSDK/latest/css

$(DOCUMENTS_DIR)/DynamoDB.html: $(DOCUMENTS_DIR)/*.css
	@curl -s $(DDB_20111205_URL) |\
		perl -pe 's/href="..\/css\//href="/g' |\
		perl -pe 's/ href="..\/_index\.html"//g' |\
		perl -pe 's/ href="(?:..\/)?(?:AWS|Service|Endpoint|Request)\.html(?:#[a-zA-Z]+-property)?"//g' |\
		perl -pe 's/(<div (?:id="search"|class="noframes"))/\1 style="display:none"/g' |\
		perl -pe 's/<a href="#" class="inheritanceTree">show all<\/a>//' |\
		perl -pe 's/<small>\(<a href="#" class="summary_toggle">collapse<\/a>\)<\/small>//g' |\
		perl -0pe 's/<(?:no)?script.+?\/(?:no)?script>//gms' \
			> $(DOCUMENTS_DIR)/DynamoDB.html &&\
		echo "Downloaded and cleaned up DynamoDB documentation HTML:\n  $(DOCUMENTS_DIR)/DynamoDB.html"

# --

$(RESOURCES_DIR)/docSet.dsidx: $(DOCUMENTS_DIR)/DynamoDB.html | $(RESOURCES_DIR)
	@sqlite3 $(RESOURCES_DIR)/docSet.dsidx '\
		CREATE TABLE searchIndex(id INTEGER PRIMARY KEY, name TEXT, type TEXT, path TEXT);\
		CREATE UNIQUE INDEX anchor ON searchIndex (name, type, path);' &&\
		echo "Created search index database:\n  $(RESOURCES_DIR)/docSet.dsidx\nPopulating..."
	@grep -q 'id="endpoint-property"' $(DOCUMENTS_DIR)/DynamoDB.html &&\
		sqlite3 $(RESOURCES_DIR)/docSet.dsidx \
			"INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES ('ddb.endpoint', 'Property', 'DynamoDB.html#endpoint-property');" &&\
		echo "  (Property) ddb.endpoint: 'DynamoDB.html#endpoint-property'"
	@for method in `cat $(DOCUMENTS_DIR)/DynamoDB.html | perl -wnE 'say for /id="((?!endpoint)\w+)-property"/g'`; do \
		sqlite3 $(RESOURCES_DIR)/docSet.dsidx \
			"INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES ('ddb.$${method}', 'Method', 'DynamoDB.html#$${method}-property');" &&\
		echo "  (Method) ddb.$${method}: 'DynamoDB.html#$${method}-property'"; \
	done