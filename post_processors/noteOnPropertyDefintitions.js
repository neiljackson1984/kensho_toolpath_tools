/* The PostProcessor class has member functions validatePropertyDefinition and validatePropertyDefinitions
   as defined below.  The code of these functions describes the requirements and possibilities of the "propertyDefinitions" property of the postProcesspor object,
   which the user is free to set.
   
   propertyDefinitions is a map whose keys are the same as the keys of the "properties" property and whose values are maps that can have the keys
        'type' - the value is expecxted to be one of ("number", "spatial", "angle", "integer", "boolean", "enum")
        'title' - the value is expected to be a string -- this is the string that will show up in the ui where, if 'title' were not specified,  the key of the properties entry would show up.
        'description' - 'this is the tooltip string that shows up in the ui when the user hovers over the line in the property table in the post process dialog.
        'group' - I suspect that this is expected to be a an integer greater than 0, but I am not 100% sure about this (I need to scrutinize the validation condition bleow more closesly to be sure).  This property might specify the order that the property is to appear in the list in the ui.
        'range' - a two-element array that is a minimum and maximum of a numeric range.
        'values' - an array of discrete allowed values that the platform consults when the type is either integer or enum.  There are several possible structures for this array.  
            in the case where type is "integer", values can be an array of numbers, or it can be ana array of elements each of which is an object with an "id" property whose value is a number and a "title" poroperty whose value is a string.
            in the case where type is "enum", values can be an array of strings, or it can be ana array of elements each of which is an object with an "id" property whose value is a string and a "title" poroperty whose value is a string. 
        'presentation' - one of ("yesno", "truefalse", "onoff", "10")

 */


function validatePropertyDefinition(id, definition) {
    var result = true;
    if (typeof id !== "string") {
        warning(subst("Identifier '%1' is not a string.", id));
        result = false;
    }
    if (definition.type === undefined) {
        warning(subst("Type for property '%1' is undefined.", id));result = false;
    }
    if (definition.title !== undefined && typeof definition.title !== "string") {
        warning(subst("Title '%1' for property '%2' is not a string.", definition.title, id));result = false;
    }
    if (definition.description !== undefined && typeof definition.description !== "string") {
        warning(subst("Description '%1' for property '%2' is not a string.", definition.description, id));
        result = false;
    }
    if (definition.group !== undefined && (typeof definition.group !== "number" || !(definition.group | 0 === definition.group))) {
        warning(subst("Group '%1' for property '%2' is not a string.", definition.group, id));
        result = false;
    }
    var range = definition.range;
    if (range !== undefined) {
        if (!(Array.isArray(range) && range.length == 2 && typeof range[0] === "number" && typeof range[1] === "number")) {
            warning(subst("Range '%1' for property '%2' is not valid.", range, id));
            result = false;
        }
    }
    var values = definition.values;
    if (values !== undefined) {
        if (!Array.isArray(values)) {
            warning(subst("Values '%1' for property '%2' is not valid.", values, id));
            result = false;
        }
   }
   var presentation = definition.presentation;
   if (presentation !== undefined) {
        if (["yesno", "truefalse", "onoff", "10"].indexOf(presentation) < 0) {
            warning(subst("Presentation '%1' for property '%2' is not valid.", presentation, id));
            result = false;
        }
   }
   switch (definition.type) {
        case "number":case "spatial":case "angle":break;
        case "integer":
            if (values !== undefined) {
                for (var vv in values) {
                    if (typeof vv === "number" && vv | 0 === vv) {
                    } else if (typeof vv === "object" && typeof vv.id === "number" && vv.id | 0 === vv.id && typeof vv.title === "string") {
                    } else { 
                        warning(subst("Integer values '%1' for property '%2' are not valid.", definition.values, id));
                        result = false;
                        break;
                    }
                }
            }
            break;
        case "boolean":
            if (range) {
                warning(subst("Range '%1' for boolean property '%2' is not supported.", range, id));result = false;
            }
            if (values) {
                if (!(Array.isArray(values) && values.length == 2 && typeof values[0] === "string" && typeof values[1] === "string")) {
                    warning(subst("Values '%1' for property '%2' is not valid.", values, id));
                    result = false;
                }
            }
            if (definition.default_mm !== undefined) {
                if (typeof definition.default_mm !== "boolean") {
                    warning(subst("Metric mode default '%1' for property '%2' is not valid.", definition.default_mm, id));
                    result = false;
                }
            }
            if (definition.default_in !== undefined) {
                if (typeof definition.default_in !== "boolean") {
                    warning(subst("Inch mode default '%1' for property '%2' is not valid.", definition.default_mm, id));
                    result = false;
                }
            }
            break;
        case "enum":
            if (range) {
                warning(subst("Range '%1' for enum property '%2' is not supported.", range, id));
                result = false;
            }
            if (values === undefined) {
                warning(subst("Enum values for property '%1' is not specified.", id));
                result = false;
            } else {
                for (var vv in values) {
                    if (typeof vv === "string") {
                    } else if (typeof vv === "object" && typeof vv.id === "string" && typeof vv.title === "string") {
                    } else {
                        warning(subst("Enum values '%1' for property '%2' are not valid.", definition.values, id));result = false;break;
                    }
                }
            }
            break;
        default:
            warning(subst("Type '%1' for property '%2' is not supported.", definition.type, id));
            result = false;
        }
    return result;
}

function validatePropertyDefinitions() {
    if (typeof propertyDefinitions !== "object") {
        return;
    }
    var failure = false;
    for (var key in propertyDefinitions) {
        if (!validatePropertyDefinition(key, propertyDefinitions[key])) {failure = true;}
    }
    if (failure) {
        error(localize("One or more property definitions are not valid."));
        return;
    }
}