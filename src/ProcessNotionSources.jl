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
            "--defining-documents"
                help = "defining documents source (CSV)"
                arg_type = String
                required = true
            "--isq-alternate-quantity-names"
                help = "ISQ altnerate quantity names source (CSV)"
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

        @info "$(now()) loading documents source $(args["defining-documents"])"
        defining_documents_csv = load_csv_document(args["sources-path-prefix"], args["defining-documents"])

       #
        # build dictionaries of input data
        #

        @info "$(now()) building defining documents dictionary"
        defining_documents = table_to_dict(defining_documents_csv, "Document")
 
        #
        # create ontologies and bundles
        #

        @info "$(now()) create ontologies"
        ontologies = construct_ontologies(defining_documents)
        knowledge["ontologies"] = ontologies

        @info "$(now()) create bundles"
        # bundles = construct_bundles(ontologies)
        # knowledge["bundles"] = bundles

        #
        # create quantity instances
        #

        @info "$(now()) create quantity instances"
        quantity_instances = Dict()
        # quantity_instances = construct_quantity_instances(quantities, ontologies, symbols)
        # knowledge["quantity_instances"] = quantity_instances

        #
        # create unit instances
        #

        @info "$(now()) create unit instances"
        unit_instances = Dict()
        # unit_instances = construct_unit_instances(units, quantities, ontologies, quantity_instances)
        # knowledge["unit_instances"] = unit_instances

        #
        # write output
        #

        @info "$(now()) saving $(length(quantity_instances)) quantities, $(length(unit_instances)) units"
        output = (args["output"] == "" ? stdout : open(args["output"], "w"))
        JSON.json(output, knowledge, pretty = true)
        
        #
        # end
        #

        @info "$(now()) end"
    end

end