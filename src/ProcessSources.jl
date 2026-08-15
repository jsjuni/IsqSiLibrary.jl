module Main

    using ArgParse
    using Logging
    using Dates
    using IsqSiLibrary

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
        end
        return parse_args(s)
    end

    function (@main)(ARGS)
         
        @info "$(now()) start"
        @info "$(now()) parse command arguments"
        args = parse_commandline()
    
        @info "$(now()) loading documents source $(args["documents-source"])"
        docs_source = joinpath(args["sources-path-prefix"], args["documents-source"])
        documents_csv = parse_csv_source(docs_source)
        @info documents_csv

        @info "$(now()) loading quantities source $(args["documents-source"])"
        docs_source = joinpath(args["sources-path-prefix"], args["quantities-source"])
        quantities_csv = parse_csv_source(docs_source)
        @info quantities_csv

        @info "$(now()) loading units source $(args["documents-source"])"
        docs_source = joinpath(args["sources-path-prefix"], args["units-source"])
        units_csv = parse_csv_source(docs_source)
        @info units_csv

        @info "$(now()) end"
    end

end