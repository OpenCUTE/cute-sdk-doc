.PHONY: serve build clean

serve:
	mkdocs serve -a 127.0.0.1:8011

build:
	mkdocs build

clean:
	rm -rf site/
