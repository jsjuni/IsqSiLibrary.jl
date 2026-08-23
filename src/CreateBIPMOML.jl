module Main

    using ArgParse
    using Logging
    using Dates
    using IsqSiLibrary
    using JSON
    using OrderedCollections
    using OMLCodeAPI
    using NamingConventions
    
    const PLURAL = Dict("quantity" => "quantities", "unit" => "units", "value" => "values")

    const TYPE_MAP = Dict(
        "Base" => SI_BASE_UNIT,
        "Special" => SI_DERIVED_UNIT,
        "One" => SI_UNIT
    )

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
            "--iri-stem"
                help = "IRI stem OML (default: si)"
                arg_type = String
                default = "si"
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
            "--creator"
                help = "Value of dc:creator annotation on ontologies and bundles"
                arg_type = String
                default = nothing
            "--title-stem"
                help = "Ontololgy title stem"
                arg_type = String
                default = "BIPM SI"
            "--source"
                help = "Source document"
                arg_type = String
                default = "The International System of Units 9th edition (2019)"
            "--si-digital-framework-ns"
                help = "SI Digital Framework namespace (for dc:relation annotations)"
                arg_type = AbstractString
                default = nothing
        end
        return parse_args(s)
    end

    function ontology_iri_ns(base, stem, separator)
        iri = joinpath(base, stem)
        ns = iri * separator
        (iri, ns)
    end

    function create_description_or_vocabulary(path_base, namespace_path, namespace_base, iri_stem, type, prefix, title, label, source; separator = "#")
        operations = []
        filename = joinpath(path_base, namespace_path, iri_stem) * ".oml"
        if isfile(filename)
            @info "$(now())   skip $filename: file exists"
            return []
        else
            (ontology_iri, ontology_namespace) = ontology_iri_ns(namespace_base, iri_stem, separator)
            @info "$(now())   create $ontology_namespace $filename"
            append!(operations, [
                create_ontology(
                    type,
                    ontology_namespace,
                    prefix,
                    path_base
                ),
                add_annotation(ontology_iri, ontology_iri, DC_TITLE, title),
                add_annotation(ontology_iri, ontology_iri, RDFS_LABEL, label),
                add_annotation(ontology_iri, ontology_iri, DC_SOURCE, source)
            ])
        end
    end

    function create_quantity_or_unit_instance(instance_data, description_iri_stem, instance_id, namespace_base, has_identifier, base_or_derived, separator)
        operations = []
        (description_iri, description_ns) = ontology_iri_ns(
            namespace_base, description_iri_stem, separator
        )
        instance_iri = description_ns * instance_id
        append!(operations, [
            create_instance(description_iri, instance_id),
            add_assertion(description_iri, instance_iri, RDF_TYPE, base_or_derived),
            add_annotation(description_iri, instance_iri, RDFS_LABEL, instance_data["name"]),
            add_assertion(description_iri, instance_iri, has_identifier, instance_data["name"]),
        ])
    end

    function capitalize(string)
        Base.Unicode.uppercasefirst(string)
    end

    function(@main)(ARGS)

        @info "$(now()) start"
        @info "$(now()) parse command arguments"
        args = parse_commandline()

        # shorter names

        namespace_base = args["namespace-base"]
        namespace_path = replace(namespace_base, r".*//" => "")
        path_base = args["path-base"]
        iri_stem = args["iri-stem"]
        separator = args["separator"]
        creator = args["creator"]
        title_stem = args["title-stem"]
        source = args["source"]
        if isnothing(args["si-digital-framework-ns"])
            si_namespace = nothing
        else
            si_namespace = replace(args["si-digital-framework-ns"], r"^<" => "", r">$" => "")
        end

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

        # create vocabulary

        @info "$(now()) create SI vocabulary"
        v_iri_stem = iri_stem * "-v"
        v_prefix = v_iri_stem
        v_title = "$title_stem vocabulary"
        v_label = v_title
        append!(stage_1,
            create_description_or_vocabulary(
                path_base,
                namespace_path,
                namespace_base,
                v_iri_stem,
                "vocabulary",
                v_prefix,
                v_title,
                v_label,
                source
            )
        )

        # create description

        @info "$(now()) create SI description"
        d_iri_stem = iri_stem * "-d"
        d_prefix = d_iri_stem
        d_title = "$title_stem description"
        d_label = d_title
        append!(stage_1,
            create_description_or_vocabulary(
                path_base,
                namespace_path,
                namespace_base,
                d_iri_stem,
                "description",
                d_prefix,
                d_title,
                d_label,
                source
            )
        )

        # process units

        @info "$(now()) process units"
        for (unit_id, unit_data) in input["unit_instances"]
            if !haskey(unit_data, "document") || unit_data["document"] != "SI Brochure" continue; end
            description_iri_stem = unit_data["description_iri_stem"]
            @info "$(now())   $(description_iri_stem) $unit_id"

            # create quantity instance

            append!(stage_1,
                create_quantity_or_unit_instance(
                    unit_data,
                    description_iri_stem,
                    unit_id,
                    namespace_base,
                    HAS_UNIT_IDENTIFIER,
                    TYPE_MAP[unit_data["type"]],
                    separator
                )
            )

            (description_iri, description_ns) = ontology_iri_ns(
                namespace_base, description_iri_stem, separator
            )
            unit_iri = description_ns * unit_id

            if !isnothing(si_namespace)
                si_name = NamingConventions.convert(SnakeCase, CamelCase, unit_id)
                @show description_iri
                @show unit_iri
                @show DC_RELATION
                @show si_namespace * si_name
                @show as_anyuri(si_namespace * si_name)
                push!(stage_1, add_annotation(description_iri, unit_iri, DC_RELATION, as_anyuri(si_namespace * si_name)))
            end

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