function createFormat(specifiers) {
    var width = 0;
    var forceSign = false;
    var forceDecimal = false;
    var zeropad = false;
    var decimals = 6;
    var trimZeroDecimals = true;
    var trimLeadZero = false;
    var decimalSymbol = ".";
    var cyclicLimit = 0;
    var cyclicSign = 0;
    var scale = 1;
    var offset = 0;
    var prefix = "";
    var suffix = "";
    if (specifiers &&
        specifiers.inherit &&
        (specifiers.inherit instanceof FormatNumber ||
        specifiers.inherit instanceof Format)) {
        var inherit = specifiers.inherit;
        if (inherit instanceof Format) {
            inherit = inherit.formatNumber;
        }
        if (inherit) {
            decimals = inherit.getNumberOfDecimals();
            trimZeroDecimals = inherit.getTrimZeroDecimals();
            trimLeadZero = inherit.getTrimLeadZero();
            width = inherit.getWidth();
            forceSign = inherit.getForceSign();
            forceDecimal = inherit.getForceDecimal();
            decimalSymbol = inherit.getDecimalSymbol();
            zeropad = inherit.getZeroPad();
            cyclicLimit = inherit.getCyclicLimit();
            if (cyclicLimit > 0) {
                cyclicSign = inherit.getCyclicSign();
            }
            scale = inherit.getScale();
            offset = inherit.getOffset();
            prefix = inherit.getPrefix();
            suffix = inherit.getSuffix();
        }
    }
    for (var name in specifiers) {
        switch (name) {
          case "decimals":
            decimals = specifiers[name];
            break;
          case "trim":
            trimZeroDecimals = specifiers[name];
            break;
          case "trimLeadZero":
            trimLeadZero = specifiers[name];
            break;
          case "forceSign":
            forceSign = specifiers[name];
            break;
          case "forceDecimal":
            forceDecimal = specifiers[name];
            break;
          case "zeropad":
            zeropad = specifiers[name];
            break;
          case "width":
            width = specifiers[name];
            break;
          case "separator":
            decimalSymbol = specifiers[name];
            break;
          case "cyclicLimit":
            cyclicLimit = specifiers[name];
            break;
          case "cyclicSign":
            cyclicSign = specifiers[name];
            break;
          case "scale":
            scale = specifiers[name];
            break;
          case "offset":
            offset = specifiers[name];
            break;
          case "prefix":
            prefix = specifiers[name];
            break;
          case "suffix":
            suffix = specifiers[name];
            break;
          default:
            warning(subst(localize("Unsupported format specifier '%1'."), name));
        }
    }
    var formatNumber = new FormatNumber;
    formatNumber.setNumberOfDecimals(decimals);
    formatNumber.setTrimZeroDecimals(trimZeroDecimals);
    formatNumber.setTrimLeadZero(trimLeadZero);
    formatNumber.setWidth(width);
    formatNumber.setForceSign(forceSign);
    formatNumber.setForceDecimal(forceDecimal);
    formatNumber.setDecimalSymbol(decimalSymbol);
    formatNumber.setZeroPad(zeropad);
    formatNumber.setCyclicMapping(cyclicLimit, cyclicSign);
    if (scale != 1) {
        formatNumber.setScale(scale);
    }
    if (offset != 0) {
        formatNumber.setOffset(offset);
    }
    if (prefix) {
        formatNumber.setPrefix(prefix);
    }
    if (suffix) {
        formatNumber.setSuffix(suffix);
    }
    return formatNumber;
}