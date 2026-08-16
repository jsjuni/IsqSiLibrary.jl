module Main

    using ArgParse
    using Logging
    using Dates
    using IsqSiLibrary
    using JSON

    function parse_commandline()
        s = ArgParseSettings()
        @add_arg_table s begin
            "--sources-path-prefix"
                help = "path prefix to sources"
                arg_type = String
                required = true
            "--documents-source"
                help = "documents source file (JSON)"
                arg_type = String
                required = true
            "--quantities-source"
                help = "quantities source file (JSON)"
                arg_type = String
                required = true
            "--units-source"
                help = "units source file (JSON)"
                arg_type = String
                required = true
            "--prefixes-source"
                help = "prefixes source file (JSON)"
                arg_type = String
                required = true
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

        @info "$(now()) loading documents source $(args["documents-source"])"
        documents_csv = load_csv_document(args["sources-path-prefix"], args["documents-source"])
 
        @info "$(now()) loading quantities source $(args["quantities-source"])"
        quantities_csv = load_csv_document(args["sources-path-prefix"], args["quantities-source"])

        @info "$(now()) loading units source $(args["units-source"])"
        units_csv = load_csv_document(args["sources-path-prefix"], args["units-source"])

        @info "$(now()) loading prefixes source $(args["prefixes-source"])"
        prefixes_csv = load_csv_document(args["sources-path-prefix"], args["prefixes-source"])

        #
        # build dictionaries of input data
        #

        @info "$(now()) building documents dictionary"
        documents = table_to_dict(documents_csv, "Document")
 
        @info "$(now()) building quantities dictionary"
        quantities = table_to_dict(quantities_csv, "Quantity")

        @info "$(now()) building units dictionary"
        units = table_to_dict(units_csv, "Unit")

        @info "$(now()) building prefixes dictionary"
        prefixes = table_to_dict(prefixes_csv, "Prefix")

        #
        # create ontologies and bundles
        #

        @info "$(now()) create ontologies"
        ontologies = construct_ontologies(documents)
        knowledge["ontologies"] = ontologies

        @info "$(now()) create bundles"
        bundles = construct_bundles(ontologies)
        knowledge["bundles"] = bundles

        #
        # create quantity instances
        #

        @info "$(now()) create quantity instances"
        quantity_instances = construct_quantity_instances(quantities, ontologies)
        knowledge["quantity_instances"] = quantity_instances

        #
        # create unit instances
        #

        @info "$(now()) create unit instances"
        unit_instances = construct_unit_instances(units, quantities, ontologies, quantity_instances)
        knowledge["unit_instances"] = unit_instances

        #
        # write output
        #

        JSON.json(stdout, knowledge, pretty = true)
        
        #
        # end
        #

        @info "$(now()) end"
    end

end