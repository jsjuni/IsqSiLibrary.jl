module ProcessBIPMUnitsSource

    using ArgParse
    using Logging
    using Dates
    using JSON
    using CSV
    using IsqSiLibrary
    using DataFrames

    const NON_SI_UNIT = "https://si-digital-framework.org/SI#nonSIUnit"
    const SI_BASE_UNIT = "https://si-digital-framework.org/SI#SIBaseUnit"
    const SI_SPECIAL_NAMED_UNIT = "https://si-digital-framework.org/SI#SISpecialNamedUnit"
    const SI_MEASUREMENT_UNIT = "https://si-digital-framework.org/SI#MeasurementUnit"

    const RDF_TYPE = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"

    const SKOS_PREFLABEL = "http://www.w3.org/2004/02/skos/core#prefLabel"

    const HAS_TYPE_STRING = "https://si-digital-framework.org/SI#hasUnitTypeAsString"
    const HAS_SYMBOL =  "https://si-digital-framework.org/SI#hasSymbol"
    const IS_UNIT_OF_QTY_KIND = "https://si-digital-framework.org/SI#isUnitOfQtyKind"
    const PREFIX_RESTRICTION = "https://si-digital-framework.org/SI#prefixRestriction"

    const SI_UNITS = [
        NON_SI_UNIT,
        SI_BASE_UNIT,
        SI_SPECIAL_NAMED_UNIT,
        SI_MEASUREMENT_UNIT 
    ]

    function parse_commandline()
        s = ArgParseSettings()
        @add_arg_table s begin
            "--units-file"
                help = "Input file (JSON)"
                arg_type = String
                required = true
        end
        return parse_args(s)
    end

    function is_unit_definition(d)
        haskey(d, RDF_TYPE) && any(map(td -> td["value"] in SI_UNITS, d[RDF_TYPE]))
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

    export main
    function (@main)(ARGS)

        #
        # process command line
        #

        @info "$(now()) start"
        @info "$(now()) parse command arguments"
        args = parse_commandline()

        units_file = args["units-file"]

        #
        # open input file
        #

        @info "$(now()) parse units file $units_file"
        input = open(units_file, "r")

        #
        # load input
        #

        @info "$(now()) parse input"
        input = JSON.parse(input)

        #
        # extract unit definitions
        #

        @info "$(now()) extract unit definitions"
        units = filter(((k, v), ) -> is_unit_definition(v), input)
        @info "$(now())   found $(length(keys(units)))"

        #
        # build value tuples
        #

        tuples = map(function(p)
                k = first(p)
                v = last(p)
                (
                    Unit = get_pref_label(v),
                    Type = get_type_string(v),
                    Symbol = get_symbol(v),
                    QuantityKind = get_quantity_kind(v),
                    PrefixRestriction = get_prefix_restriction(v),
                    URI = k
                )
            end,
            collect(units)
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
using .ProcessBIPMUnitsSource