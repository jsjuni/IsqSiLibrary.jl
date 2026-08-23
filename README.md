# IsqSiLibrary.j

# Overview

This project provides tooling to create OML vocabularies for ISQ and SI.

# Architectural Notes

## Objectives

### Phase 1
The initial focus is to construct OML vocabularies and descriptions (and corresponding SysML libraries) sufficient to provide metrological type safety in user models. See the discussion on this topic below.

### Phase 2
A second enhancement will provide information useful for converting values from one unit to some other compatible unit.

### Phase 3
Later enhancements may provide further provenance information not strictly necessary for type safety.

## Origin Data

The upstream machine-readable input data is a set of CSV files exported from a hand-curated Notion workspace with databases for, among other things, quantities and units as described in SI and ISQ.

## Authority

1. BIPM is authoritative for SI units and some quantities. The source document is the [SI Brochure](https://www.bipm.org/en/si-brochure-9).
1. ISO/IEC is authoritative for ISQ/IEC quantities and their relations to SI units. The source documents are the respective [ISO/IEC 80000 standards](https://www.iso.org/search.html?PROD_isoorg_en%5Bquery%5D=80000&PROD_isoorg_en%5Bmenu%5D%5Bfacet%5D=standard). At present we do not have access to the current versions of several standards.
1. The core concepts and properties for quantities, units, systems of quantities, and systems of units are established in the [International vocabulary of metrology – Basic and general concepts and associated terms
(VIM), 3rd edition](https://www.bipm.org/documents/20126/2071204/JCGM_200_2012.pdf/f0e1ad45-d337-bbeb-53a6-15fe649d0ff1). We refer to this document as VIM3.

## Metrological Type Safety

The fundamental notion of metrological type safety is that a quantity, e.g. _vehicle_mass_, has a type (VIM3 calls it _kind of quantity_). Any value that purports to measure the magnitude of _vehicle_mass_ must be expressed in a unit appropriate for that quantity.

BIPM defines the unit `kg` as one of the base units of SI. ISO 80000 Part 4 defines a quantity kind _mass_ (they call it a quantity) and says any values of a quantity of the same kind as _mass_ must have a unit of the same kind. Moreover, Part 4 says that `kg` is the same kind as _mass_.

That is necessary but not sufficient for type safety. Sufficiency comes from disjointness assertions that say, among other things, that `kg` is not (also) of the same kind as, say, _length_.

For type safety it is not necessary to know that, e.g. 1 kg = 1000 g as long as `kg` and `g` are the same kind as _mass_. That knowledge is useful for computations involving expressions with mixed units and so will be added in Phase 2.

Neither type safety nor computation require the knowledge that, e.g., `m³` is formally defined as the unit `m` raised to the third power, or `farad` is defined as `kg⁻¹ m⁻² s⁴ A²`. If such knowledge is added to the ontologies, it will be in separate descriptions that need not be brought into the scope of reasoning.

## Named Units and Unit Expressions

BIPM formally defines seven _base_ units and 22 so-called _special named units_. They do not formally define (although they refer to) the unit _one_. Modeling of so-called _quantities of unit one_, however, requires a reference that that unit. Consequently we formally define _one_ and attribute it to BIPM as neither a _base_ nor _special_named_unit_.

Many quantities, e.g., _volume_ (Part 3) and _dynamic viscosity_ (Part 4) have associated units that are expressions of defined units: `m³` and `Pa s`. The ISO/IEC 80000 standards simply refer to these expressions literally and anonymously. For modeling economy, however, it is important to give each unique expression an identifier and a definition to which all uses can refer. The set of unique expressions will be collected across all ISO/IEC 80000 parts and defined in a single description attributed to ISO/IEC. This description will be imported by part vocabularies and descriptions, but will not import and part-specific ontologies. This allows the modeler to select a bundle of Parts 3 and 4 only without having to include unnecessary parts.

## Prefixed Units

In some ways the simplest approach would be to mechanically-define every valid combiation of a named unit and a defined prefix. That will result in 720 defined prefixed units, which is not an outrageous number. In any case, whatever prefixed units are defined will go in one or more separate descriptions.

## Non-SI Units

We will include the non-SI units accepted for use by the BIPM. This raises an ambiguity, however, whose proposed solution raises another ambiguity.

### Conflicting Unit Names

BIPM defines two non-SI units named _minute_: one for time, the other for plane angle. Similarly for _second_.

In the implementation so far, the unit name is used as a key within the SI system: no two units in SI may have the same name. One easy way to resolve this conflict is to use both the name and quantity kind as the key.

That requires adding the list of quantity (kinds) defined by BIPM to the input data, which is not it itself a problem. The problem that arises now is the relation between quantities defined by BIPM and those defined by ISO/IEC.

One straightforward solution may be simply to declare, when appropriate, that an ISO/IEC quantity specializes its corresponding BIPM quantity. This should be straightforward to implement in the current approach because each quantity kind is represented by a class, an archetypal instance of that class, and a rule that states all members of that class are of the same kind as the archetypal instance. This specialization relationship is expressed simply as a subclass relation.

Unfortunately, there does not appear to be a reliable way to map ISO/IEC quantities to BIPM quantites except by inspecting name similarity.

This technique may resolve another issue, and that is how to deal with ISO/IEC quantities that are grouped by subitem number, e.g., 4-28.1 potential energy, 4-28.2 kinetic energy, 4-28.3 mechanical energy, and 4-28.4 mechanical work can be effectively grouped by making them all distinct subclasses of BIPM energy.

## Vocabulary Extensions

The generated vocabularies will make it convenient for modelers to instantiate quantities by simply declaring them to be members of a particular quantity kind class. That will suffice to ensure type safety of all purported values of that quantity.

## Tensor Shape and Type

TBD
