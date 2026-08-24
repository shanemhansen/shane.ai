EMACS      ?= emacs
HUGO       := $(CURDIR)/bin/hugo
DOCS_DIR   := docs
ORG_SRC    := $(DOCS_DIR)/content-org/all-posts.org

# docs/content-org/all-posts.org is the single source of truth for all posts.
# Each post is a top-level heading with an EXPORT_FILE_NAME property; ox-hugo
# exports every such subtree to a markdown file under docs/content/posts.
# ob-dot must be loaded so its built-in (:exports . "results") default
# applies to the literate `dot` diagrams (they render as images, not code).
EXPORT_ELISP := (progn \
	(require 'package) (package-initialize) \
	(require 'ob-dot) \
	(require 'ox-hugo) \
	(org-hugo-export-wim-to-md t))

.PHONY: all posts build serve clean

all: build

posts:
	$(EMACS) --batch $(ORG_SRC) --eval "$(EXPORT_ELISP)"

build: posts
	cd $(DOCS_DIR) && $(HUGO) --minify

serve: posts
	cd $(DOCS_DIR) && $(HUGO) server -D

clean:
	rm -rf $(DOCS_DIR)/public
