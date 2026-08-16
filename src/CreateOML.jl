module Main

    using ArgParse
    using Logging
    using Dates
    using IsqSiLibrary
    using JSON
    using OrderedCollections
    using OMLCodeAPI

    function parse_commandline()
        s = ArgParseSettings()
        @add_arg_table s begin
            "--input"
                help = "path prefix to input JSON"
                arg_type = String
                required = true
            "--server"
                help = "Column name for server URL (default: http://127.0.0.1:8080)"
                arg_type = String
                default = "http://127.0.0.1:8080"
            "--path-base"
                help = "OML source path base (default: src/oml/model)"
                arg_type = String
                default = "src/model/oml"
            "--namespace-base"
                help = "Base namespace for OML (default: http://studioj.us/mass-props-oml)"
                arg_type = String
                default = "http://studioj.us/mass-props-oml"
            "--separator"
                help = "Namespace separator (default: #)"
                arg_type = String
                default = "#"
            "--defer-diagnostics"
                help = "Defer diagnostics until the end (default: false)"
                action = :store_true
            "--inhibit-updates"
                help = "Inhibit updates to server (default: false)"
                action = :store_true
        end
        return parse_args(s)
    end

    function ontology_iri_ns(base, stem, separator)
        iri = joinpath(base, stem)
        ns = iri * separator
        (iri, ns)
    end

    function(@main)(ARGS)

        @info "$(now()) start"
        @info "$(now()) parse command arguments"
        args = parse_commandline()

        # check server status

        server = args["server"]
        @info "$(now()) check server status at $server"
        if !is_alive(server)
            @error "Server is not alive at " args["server"]
            exit(1)
        end

        # load input

        input_filename = args["input"]
        @info "$(now()) load input from $input_filename"
        input_file = open(input_filename, "r")

        input = JSON.parse(input_file)

        stage_1 = []
        stage_2 = []

        operations = OrderedDict(
            "stage 1" => stage_1,
            "stage 2" => stage_2
        )

        # create ontologies

        @info "$(now()) create ontologies"
        for (ontology_id, ontology_data) in input["ontologies"]
            (ontology_iri, ontology_namespace) = ontology_iri_ns(args["namespace-base"], ontology_data["iri_stem"], args["separator"])
            @info "$(now())   create $ontology_id $ontology_namespace"
            push!(stage_1, 
                create_ontology(
                    ontology_data["type"],
                    ontology_namespace,
                    ontology_data["prefix"],
                    args["path-base"]
                )
            )
        end

        # create bundles

        @info "$(now()) create bundles"
        for (bundle_id, bundle_data) in input["bundles"]
            (bundle_iri, bundle_namespace) = ontology_iri_ns(args["namespace-base"], bundle_data["iri_stem"], args["separator"])
            @info "$(now())   create $bundle_id $bundle_namespace"
            push!(stage_1,
                create_ontology(
                    bundle_data["type"],
                    bundle_namespace,
                    bundle_data["prefix"],
                    args["path-base"]
                )
            )
            for imprt in bundle_data["imports"]
                (imprt_iri, unused) = ontology_iri_ns(args["namespace-base"], imprt, args["separator"])
                @info "$(now())     add import for $imprt"
                push!(stage_2, add_import(bundle_iri, imprt_iri))
            end
        end

        # process quantities

        @info "$(now()) process quantities"
        for (quantity_id, quantity_data) in input["quantity_instances"]
            (vocabulary_iri, unused) = ontology_iri_ns(
                args["namespace-base"], quantity_data["vocabulary_iri_stem"], args["separator"]
            )
            (description_iri, unused) = ontology_iri_ns(
                args["namespace-base"], quantity_data["description_iri_stem"], args["separator"]
            )
             @info "$(now())   $description_iri $quantity_id"

            # create quantity instance
            push!(stage_1, create_instance(description_iri, quantity_id))

            # create quantity classes

       end

        # process units

        @info "$(now()) process units"
        for (unit_id, unit_data) in input["unit_instances"]
            (vocabulary_iri, unused) = ontology_iri_ns(
                args["namespace-base"], unit_data["vocabulary_iri_stem"], args["separator"]
            )
            (description_iri, unused) = ontology_iri_ns(
                args["namespace-base"], unit_data["description_iri_stem"], args["separator"]
            )
             @info "$(now())   $description_iri $unit_id"

            # create unit instance
            push!(stage_1, create_instance(description_iri, unit_id))

            # create unit classes
 
        end

        # update server

        if args["inhibit-updates"]
            @info "$(now()) server updates inhibited"
        else
            @info "$(now()) update server"
            for (name, ops) in operations
                @info "$(now())   $name $(length(ops)) operations"
                update(server, ops, args["defer-diagnostics"])
            end
        end

        # end

        @info "$(now()) end"

    end

end