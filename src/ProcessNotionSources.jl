module Main

    using ArgParse
    using Logging
    using Dates
    using IsqSiLibrary
    using JSON

    # "--defining-documents", "Defining Documents ff3fbbe356d348cfb81f1038b92ce8fe.csv",
    # "--isq-alternate-quantity-names", "ISQ Alternate Quantity Names 3bfb24cf917a807b894aef90b1c6b03d.csv",
    # "--isq-quantities", "ISQ Quantities e1b3e75b0f85444aa01339cbc9e867df.csv",
    # "--isq-quantity-symbols", "ISQ Quantity Symbols 3c0b24cf917a807a8b41fd799eb11f3b.csv",
    # "--isq-units", "ISQ Units b419c70b1bf040e3b87a04a900378d01.csv",
    # "--si-prefixes", "SI Prefixes 00b23fe2521d407688f118fd44e4e1f1.csv",
    # "--si-quantities", "SI Quantities 32cde0fb98d64a7eb326541295d6828a.csv",
    # "--si-units", "SI Units 998717c59d0a4afb812373ff5eed110b.csv",
 
    function parse_commandline()
        s = ArgParseSettings()
        @add_arg_table s begin
            "--sources-path-prefix"
                help = "path prefix to sources"
                arg_type = String
                required = true
            "--authorities"
                help = "authorities source (CSV)"
                arg_type = String
                required = true
            "--defining-documents"
                help = "defining documents source (CSV)"
                arg_type = String
                required = true
            "--ontology-bundles"
                help = "ontology bundles source (CSV)"
                arg_type = String
                required = true
            "--isq-alternate-quantity-names"
                help = "ISQ alternate quantity names source (CSV)"
                arg_type = String
                required = true
            "--isq-quantities"
                help = "ISQ quantities source (CSV)"
                arg_type = String
                required = true
            "--isq-quantity-symbols"
                help = "ISQ quantity symbols source (CSV)"
                arg_type = String
                required = true
            "--isq-units"
                help = "ISQ units source (CSV)"
                arg_type = String
                required = true
            "--si-prefixes"
                help = "SI prefixes source (CSV)"
                arg_type = String
                required = true
            "--si-quantities"
                help = "SI quantities source (CSV)"
                arg_type = String
                required = true
            "--si-units"
                help = "SI units source (CSV)"
                arg_type = String
                required = true
            "--output"
                help = "Output JSON file (default: output.json)"
                arg_type = String
                default = ""
        end
        return parse_args(s)
    end

    function load_csv_document(prefix, path)
       parse_csv_source(joinpath(prefix, path))
    end

    function (@main)(ARGS)

        knowledge = initialize_dictionary()

        @info "$(now()) start"
        @info "$(now()) parse command arguments"
        args = parse_commandline()
    
        #
        # parse input data sources
        #

        @info "$(now()) loading authorities source $(args["authorities"])"
        authorities_df = load_csv_document(args["sources-path-prefix"], args["authorities"])

        @info "$(now()) loading documents source $(args["defining-documents"])"
        defining_documents_df = load_csv_document(args["sources-path-prefix"], args["defining-documents"])

        @info "$(now()) loading ontology bundles source $(args["ontology-bundles"])"
        ontology_bundles_df = load_csv_document(args["sources-path-prefix"], args["ontology-bundles"])

        @info "$(now()) loading si quantities source $(args["si-quantities"])"
        si_quantities_df = load_csv_document(args["sources-path-prefix"], args["si-quantities"])

        @info "$(now()) loading si units source $(args["si-units"])"
        si_units_df = load_csv_document(args["sources-path-prefix"], args["si-units"])

        @info "$(now()) loading isq quantities source $(args["isq-quantities"])"
        isq_quantities_df = load_csv_document(args["sources-path-prefix"], args["isq-quantities"])

        @info "$(now()) loading si units source $(args["isq-units"])"
        isq_units_df = load_csv_document(args["sources-path-prefix"], args["isq-units"])

        #
        # create authorities
        #

        @info "$(now()) create authorities"
        authorities = construct_authorities(authorities_df)
        knowledge["authorities"] = authorities

        #
        # create ontologies and bundles
        #

        @info "$(now()) create ontologies"
        ontologies = construct_ontologies(authorities, defining_documents_df)
        knowledge["ontologies"] = ontologies

        @info "$(now()) create bundles"
        bundles = construct_bundles(authorities, ontologies, ontology_bundles_df)
        knowledge["bundles"] = bundles

        #
        # create si entities
        #

        @info "$(now()) create si entities"
        si_entities = construct_si_entities(ontologies, si_quantities_df, si_units_df)
        knowledge["si_entities"] = si_entities

        #
        # create si entities
        #

        @info "$(now()) create isq entities"
        isq_entities = construct_isq_entities(ontologies, si_quantities_df, si_units_df, isq_quantities_df, isq_units_df)
        knowledge["isq_entities"] = isq_entities

        #
        # write output
        #

        @info "$(now()) saving $(length(si_entities)) si entities, $(length(isq_entities)) isq entities"
        output = (args["output"] == "" ? stdout : open(args["output"], "w"))
        JSON.json(output, knowledge, pretty = true)
        
        #
        # end
        #

        @info "$(now()) end"
    end

end