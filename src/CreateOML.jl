module Main

    using ArgParse
    using Logging
    using Dates
    using IsqSiLibrary
    using JSON
    using OrderedCollections
    using OMLCodeAPI

    const DC_DESCRIPTION = "<http://purl.org/dc/elements/1.1/description>"
    const DC_SOURCE = "<http://purl.org/dc/elements/1.1/source>"
    const DC_TITLE = "<http://purl.org/dc/elements/1.1/title>"

    const RDFS_LABEL = "<http://www.w3.org/2000/01/rdf-schema#label>"

    const HAS_QUANTITY_IDENTIFIER = "<http://iso.org/iso-80000/1-v#hasQuantityIdentifier>"
    const HAS_UNIT_IDENTIFIER = "<http://iso.org/iso-80000/1-v#hasUnitIdentifier>"

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

    function create_quantity_or_unit_instance(instance_data, instance_id, namespace_base, has_identifier, separator)
        operations = []
        (description_iri, description_ns) = ontology_iri_ns(
            namespace_base, instance_data["description_iri_stem"], separator
        )
        instance_iri = description_ns * instance_id
        push!(operations, create_instance(description_iri, instance_id))
        push!(operations, add_annotation(description_iri, instance_iri, RDFS_LABEL, instance_data["name"]))
        push!(operations, add_annotation(description_iri, instance_iri, DC_DESCRIPTION, instance_data["description"]))
        push!(operations, add_assertion(description_iri, instance_iri, has_identifier, instance_data["name"]))
    end

    function(@main)(ARGS)

        @info "$(now()) start"
        @info "$(now()) parse command arguments"
        args = parse_commandline()

        # shorter names

        namespace_base = args["namespace-base"]
        separator = args["separator"]

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

        # find ontologies required by quantities defined

        instances = mapfoldl(k -> values(input[k]), append!, ["quantity_instances", "unit_instances"], init =[])
        ontology_iri_stems = Set(Iterators.flatmap(d -> (d["vocabulary_iri_stem"], d["description_iri_stem"]), instances))

        # create ontologies

        @info "$(now()) create ontologies"
        for (ontology_id, ontology_data) in input["ontologies"]
            if ontology_data["iri_stem"] in ontology_iri_stems
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
                push!(stage_1,
                    add_annotation(ontology_iri, ontology_iri, DC_TITLE, ontology_id)
                )
                push!(stage_1,
                    add_annotation(ontology_iri, ontology_iri, RDFS_LABEL, ontology_data["label"])
                )
                 push!(stage_1,
                    add_annotation(ontology_iri, ontology_iri, DC_SOURCE, ontology_data["source"])
                )
            end
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
            @info "$(now())     $(quantity_data["description_iri_stem"]) $quantity_id"

            # create quantity instance

            append!(stage_1,
                create_quantity_or_unit_instance(quantity_data, quantity_id, namespace_base, HAS_QUANTITY_IDENTIFIER, separator)
            )

            # create quantity classes

       end

        # process units

        @info "$(now()) process units"
        for (unit_id, unit_data) in input["unit_instances"]
            @info "$(now())     $(unit_data["description_iri_stem"]) $unit_id"

            # create quantity instance

            append!(stage_1,
                create_quantity_or_unit_instance(unit_data, unit_id, namespace_base, HAS_UNIT_IDENTIFIER, separator)
            )

            # create quantity classes

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