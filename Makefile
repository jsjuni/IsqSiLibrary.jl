RAPPER = rapper

BIPM_SOURCES = ./resource/bipm.org/knowledge_graphs
STAGE_1_OUTPUT = ./build/bipm.org/stage_1
STAGE_2_OUTPUT = ./build/bipm.org/stage_2

all:

#
#
#    S T A G E   1
#
#
# Stage 1 transforms the BIPM SI Digital Reference Point .ttl files
# into JSON. This would not be necessary if Julia had a Turtle parser,
# but to my knowledge it does not.
#
# This stage uses the $(RAPPER) RDF parser utility to translate to JSON.

.PHONY:	stage_1

stage_1: $(STAGE_1_OUTPUT)/units.json
stage_1: $(STAGE_1_OUTPUT)/quantities.json

$(STAGE_1_OUTPUT):
	mkdir -p $(STAGE_1_OUTPUT)

$(STAGE_1_OUTPUT)/units.json: $(STAGE_1_OUTPUT)
$(STAGE_1_OUTPUT)/quantities.json: $(STAGE_1_OUTPUT)

$(STAGE_1_OUTPUT)/units.json: $(BIPM_SOURCES)/SI_Reference_Point/units.ttl
	$(RAPPER) -i turtle -o json $< > $@

$(STAGE_1_OUTPUT)/quantities.json: $(BIPM_SOURCES)/quantities/quantities.ttl
	$(RAPPER) -i turtle -o json $< > $@

#
#
#    S T A G E   2
#
#
# Stage 2 transforms the output of Stage 1 into CSV files suitable for
# import to Notion.

.PHONY: stage_2

stage_2: $(STAGE_2_OUTPUT)/units.csv
stage_2: $(STAGE_2_OUTPUT)/quantities.csv

$(STAGE_2_OUTPUT):
	mkdir -p $(STAGE_2_OUTPUT)

$(STAGE_2_OUTPUT)/units.csv: $(STAGE_2_OUTPUT)
$(STAGE_2_OUTPUT)/quantities.csv: $(STAGE_2_OUTPUT)

$(STAGE_2_OUTPUT)/units.csv: $(STAGE_1_OUTPUT)/units.json
	julia --project=. -- src/ProcessBIPMUnitsSource.jl --units-file $< > $@

$(STAGE_2_OUTPUT)/quantities.csv: $(STAGE_1_OUTPUT)/quantities.json $(STAGE_2_OUTPUT)/units.csv
	julia --project=. -- src/ProcessBIPMQuantitiesSource.jl \
		--quantities-file $(STAGE_1_OUTPUT)/quantities.json \
		--units-table $(STAGE_2_OUTPUT)/units.csv > $@


