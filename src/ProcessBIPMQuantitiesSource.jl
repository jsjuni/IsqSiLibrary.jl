module ProcessBIPMQuantitiesSource

    using ArgParse
    using Logging
    using Dates
    using JSON
    using CSV
    using IsqSiLibrary
    using DataFrames

    const QUANTITY_KIND = "https://si-digital-framework.org/SI#QuantityKind"

    const RDF_TYPE = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"

    const SKOS_PREFLABEL = "http://www.w3.org/2004/02/skos/core#prefLabel"
    const SKOS_ALTLABEL = "http://www.w3.org/2004/02/skos/core#altLabel"

    const HAS_UNIT = "https://si-digital-framework.org/SI#hasUnit"
    const UNIT_PRODUCT = "https://si-digital-framework.org/SI#UnitProduct"
    const UNIT_POWER = "https://si-digital-framework.org/SI#UnitPower"
    const HAS_LEFT_UNIT_TERM = "https://si-digital-framework.org/SI#hasLeftUnitTerm"
    const HAS_RIGHT_UNIT_TERM = "https://si-digital-framework.org/SI#hasRightUnitTerm"
    const HAS_NUMERIC_EXPONENT = "https://si-digital-framework.org/SI#hasNumericExponent"
    const HAS_UNIT_BASE = "https://si-digital-framework.org/SI#hasUnitBase"

    const SUPERSCRIPT_MAP = Dict(
        "-" => "⁻",
        "0" => "⁰",
        "1" => "¹",
        "2" => "²",
        "3" => "³",
        "4" => "⁴",
        "5" => "⁵",
        "6" => "⁶",
        "7" => "⁷",
        "8" => "⁸",
        "9" => "⁹"
    )

    function parse_commandline()
        s = ArgParseSettings()
        @add_arg_table s begin
            "--quantities-file"
                help = "Input file (JSON)"
                arg_type = String
                required = true
            "--units-table"
                help = "Units table (CSV)"
                arg_type = String
                required = true
        end
        return parse_args(s)
    end

    function is_quantity_definition(d)
        haskey(d, RDF_TYPE) && any(map(td -> td["value"] == QUANTITY_KIND, d[RDF_TYPE]))
    end

    function get_string(d, key)
        if haskey(d, key)
            return first(d[key])["value"]
        else
            return missing
        end
     end

    function get_lang_string(d, key)
        if haskey(d, key)
            for vd in d[key]
                if vd["lang"] == "en"
                    return vd["value"]
                end
            end
            return missing
        else
            return missing
        end
    end

    function get_boolean(d, key)
        get_string(d, key) == "true"
    end

    function get_alt_label(d)
        get_string(d, SKOS_ALTLABEL)
    end

    function get_pref_label(d)
        get_lang_string(d, SKOS_PREFLABEL)
    end

    function get_type_string(d)
        get_lang_string(d, HAS_TYPE_STRING)
    end

    function get_symbol(d)
        get_string(d, HAS_SYMBOL)
    end
    
    function get_quantity_kind(d)
        get_string(d, IS_UNIT_OF_QTY_KIND)
    end

    function get_prefix_restriction(d)
        get_boolean(d, PREFIX_RESTRICTION)
    end

    function construct_unit_expression(d, input, units)
        if isa(d, JSON.Object)
            if haskey(d, "type")
                t = d["type"]
                if t == "uri"
                    first(units[units.URI .== d["value"], :Symbol])
                elseif t == "bnode"
                    construct_unit_expression(input[d["value"]], input, units)
                else
                    error("unknown type")
                end
            elseif haskey(d, RDF_TYPE)
                tt = first(d[RDF_TYPE])["value"]
                if tt == UNIT_PRODUCT
                    l = first(d[HAS_LEFT_UNIT_TERM])
                    lu = construct_unit_expression(l, input, units)
                    r = first(d[HAS_RIGHT_UNIT_TERM])
                    ru = construct_unit_expression(r, input, units)
                    "$lu $ru"
                elseif tt == UNIT_POWER
                    b = first(d[HAS_UNIT_BASE])
                    bu = construct_unit_expression(b, input, units)
                    e = first(d[HAS_NUMERIC_EXPONENT])["value"]
                    "$bu$e"
                else
                    error("unknown rdf type")
                end
            else
                error("unknown d type")
            end
        else
            error("not json object")
        end
    end

    function make_superscripts(string)
        foldl(
            (s, (k, v)) -> replace(s, k => v),
            SUPERSCRIPT_MAP,
            init = string
        )
    end

    function get_unit(d, input, units)
        if haskey(d, HAS_UNIT)
            make_superscripts(construct_unit_expression(first(d[HAS_UNIT]), input, units))
        else
            missing
        end
    end

    export main
    function (@main)(ARGS)

        #
        # process command line
        #

        @info "$(now()) start"
        @info "$(now()) parse command arguments"
        args = parse_commandline()

        quantities_file = args["quantities-file"]
        units_table = args["units-table"]

        #
        # open input file
        #

        @info "$(now()) parse quantities file $quantities_file"
        input = open(quantities_file, "r")

        #
        # load input
        #

        @info "$(now()) parse input"
        input = JSON.parse(input)

        #
        # load units table
        #

        units = CSV.read(units_table, DataFrame)

        #
        # extract quantity definitions
        #

        @info "$(now()) extract quantity definitions"
        quantities = filter(((k, v), ) -> is_quantity_definition(v), input)
        @info "$(now())   found $(length(keys(quantities)))"

        #
        # build value tuples
        #

        tuples = map(function(p)
                k = first(p)
                v = last(p)
                (
                    QuantityKind = get_pref_label(v),
                    Label = get_alt_label(v),
                    Unit = get_unit(v, input, units),
                    URI = k
                )
            end,
            collect(quantities)
        )

        #
        # create CSV table
        #

        data_frame = DataFrame(tuples)

        #
        # write output
        #

        @info "$(now()) writing output"
        CSV.write(stdout, data_frame)
        
        #
        # end
        #

        @info "$(now()) end"
    end

end
using .ProcessBIPMQuantitiesSource