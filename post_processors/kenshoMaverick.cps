/**
  Mach3Mill post processor configuration. for HSMWorks.
  
  

*/
// include(findFile("decimal.js"));
include("decimal.js");
// include("math.min.js");
description = "Kensho Maverick";
vendor = "Kensho";
vendorUrl = "http://kenshoint.com";
legal = "";
description="Kensho Maverick";
certificationLevel = 2;
//minimumRevision = 24000;

extension = "gcode";
setCodePage("ascii");
var lastCoordinates = [undefined, undefined, undefined, undefined, undefined, undefined];  //unfortuantely, there is no function to retriev the angular coordinates of the current machine state (for the positional coordinates, we have PostProcessor::getCurrentPosition())
//therefore, we have to keep track of the current angular coordinates manually with lastAngularCoordinates, and update it manually whenever a motion handler is called.
//(I had originally thought that getCurrentDirection() returned the triple of angular coordinates, but it actually returns a direction vectr, or so it seems.
//ideally, I would tap into whatever internal comprehension of the angular coordinates hsmworks has, rather than intitialize lastAngularCoordinates blindly here to zero.
var retracted = false; // specifies that the tool has been retracted to the safe plane
var modifyToolOrientationInPostProcessing = false; //this is flag that we will set at the beginning of each section depending on the presence of a magic string ("modifyToolOrientationInPostProcessing") in the section's section comment.
// moveTo() will pay attention to this flag and will change the toolpath from that specified in the arguments -- this is a hack to achieve a 'rotary' strategy 4-axis toolpath based on a specially-constructed "trace" toolpath defined in hsmworks.

// var globalParameters = {}; //we will collect global paramters in here.
// var sectionParametersBySection = []; //we will collect section parameters in here -- one object appended to the array every time a new section happens.
var parameterNames = [];

var debugging = false;
// var debugMode = true;

var angularCoordinateOffset = [0,0,0];
//when HSMworks passes angular coordinates a,b,c as an argument to one of the motion funtions (onLinear5D or onRapid5D),
// we will drive the machine to angular coordinates [a + angularCoordinateOffset[0], b+ angularCoordinateOffset[1], c+angularCoordinateOffset[2]].
//this provides a work-around to hsmworks's tendency to command the machine to go to the angular coordinates closest to zero when starting a 
// 4-axis or 5-axis section that follows a 3-axis section.  -when this happens, we know where the machine is because we have been keeping track manually, and we can
// then set angularCoordinateOffset to have entries that are integer multiples of 2*PI closest to our known current angular coordinates.

//we insert thesed do-nothing M-codes in the g-code
// on their own line,
// to be picked up by the syntax highlighter in notepad++ as 
// folding delimiters.
// we will put an opening delimiter at the beginning of each section and a closing delimiter at the end of each section, so that sections may be folded in notepad++.
var doNothingOpener="M401";
var doNothingCloser="M400";

/*
Boolean mapToWCS 
Specifies that the section work plane should be mapped to the WCS. When disabled the post is responsible for handling the WCS and section work plane. By default this is enabled. 
*/
mapToWCS = false;


/*log
Boolean mapWorkOrigin 
Specifies that the section origin should be mapped to (0, 0, 0). When disabled the post is responsible for handling the section origin. By default this is enabled. 
*/
mapWorkOrigin = false;




/* global window, exports, define */

!function() {
    'use strict'

    var re = {
        not_string: /[^s]/,
        not_bool: /[^t]/,
        not_type: /[^T]/,
        not_primitive: /[^v]/,
        number: /[diefg]/,
        numeric_arg: /[bcdiefguxX]/,
        json: /[j]/,
        not_json: /[^j]/,
        text: /^[^\x25]+/,
        modulo: /^\x25{2}/,
        placeholder: /^\x25(?:([1-9]\d*)\$|\(([^)]+)\))?(\+)?(0|'[^$])?(-)?(\d+)?(?:\.(\d+))?([b-gijostTuvxX])/,
        key: /^([a-z_][a-z_\d]*)/i,
        key_access: /^\.([a-z_][a-z_\d]*)/i,
        index_access: /^\[(\d+)\]/,
        sign: /^[+-]/
    }

    function sprintf(key) {
        // `arguments` is not an array, but should be fine for this call
        return sprintf_format(sprintf_parse(key), arguments)
    }

    function vsprintf(fmt, argv) {
        return sprintf.apply(null, [fmt].concat(argv || []))
    }

    function sprintf_format(parse_tree, argv) {
        var cursor = 1, tree_length = parse_tree.length, arg, output = '', i, k, ph, pad, pad_character, pad_length, is_positive, sign
        for (i = 0; i < tree_length; i++) {
            if (typeof parse_tree[i] === 'string') {
                output += parse_tree[i]
            }
            else if (typeof parse_tree[i] === 'object') {
                ph = parse_tree[i] // convenience purposes only
                if (ph.keys) { // keyword argument
                    arg = argv[cursor]
                    for (k = 0; k < ph.keys.length; k++) {
                        if (arg == undefined) {
                            throw new Error(sprintf('[sprintf] Cannot access property "%s" of undefined value "%s"', ph.keys[k], ph.keys[k-1]))
                        }
                        arg = arg[ph.keys[k]]
                    }
                }
                else if (ph.param_no) { // positional argument (explicit)
                    arg = argv[ph.param_no]
                }
                else { // positional argument (implicit)
                    arg = argv[cursor++]
                }

                if (re.not_type.test(ph.type) && re.not_primitive.test(ph.type) && arg instanceof Function) {
                    arg = arg()
                }

                if (re.numeric_arg.test(ph.type) && (typeof arg !== 'number' && isNaN(arg))) {
                    throw new TypeError(sprintf('[sprintf] expecting number but found %T', arg))
                }

                if (re.number.test(ph.type)) {
                    is_positive = arg >= 0
                }

                switch (ph.type) {
                    case 'b':
                        arg = parseInt(arg, 10).toString(2)
                        break
                    case 'c':
                        arg = String.fromCharCode(parseInt(arg, 10))
                        break
                    case 'd':
                    case 'i':
                        arg = parseInt(arg, 10)
                        break
                    case 'j':
                        arg = JSON.stringify(arg, null, ph.width ? parseInt(ph.width) : 0)
                        break
                    case 'e':
                        arg = ph.precision ? parseFloat(arg).toExponential(ph.precision) : parseFloat(arg).toExponential()
                        break
                    case 'f':
                        arg = ph.precision ? parseFloat(arg).toFixed(ph.precision) : parseFloat(arg)
                        break
                    case 'g':
                        arg = ph.precision ? String(Number(arg.toPrecision(ph.precision))) : parseFloat(arg)
                        break
                    case 'o':
                        arg = (parseInt(arg, 10) >>> 0).toString(8)
                        break
                    case 's':
                        arg = String(arg)
                        arg = (ph.precision ? arg.substring(0, ph.precision) : arg)
                        break
                    case 't':
                        arg = String(!!arg)
                        arg = (ph.precision ? arg.substring(0, ph.precision) : arg)
                        break
                    case 'T':
                        arg = Object.prototype.toString.call(arg).slice(8, -1).toLowerCase()
                        arg = (ph.precision ? arg.substring(0, ph.precision) : arg)
                        break
                    case 'u':
                        arg = parseInt(arg, 10) >>> 0
                        break
                    case 'v':
                        arg = arg.valueOf()
                        arg = (ph.precision ? arg.substring(0, ph.precision) : arg)
                        break
                    case 'x':
                        arg = (parseInt(arg, 10) >>> 0).toString(16)
                        break
                    case 'X':
                        arg = (parseInt(arg, 10) >>> 0).toString(16).toUpperCase()
                        break
                }
                if (re.json.test(ph.type)) {
                    output += arg
                }
                else {
                    if (re.number.test(ph.type) && (!is_positive || ph.sign)) {
                        sign = is_positive ? '+' : '-'
                        arg = arg.toString().replace(re.sign, '')
                    }
                    else {
                        sign = ''
                    }
                    pad_character = ph.pad_char ? ph.pad_char === '0' ? '0' : ph.pad_char.charAt(1) : ' '
                    pad_length = ph.width - (sign + arg).length
                    pad = ph.width ? (pad_length > 0 ? pad_character.repeat(pad_length) : '') : ''
                    output += ph.align ? sign + arg + pad : (pad_character === '0' ? sign + pad + arg : pad + sign + arg)
                }
            }
        }
        return output
    }

    var sprintf_cache = Object.create(null)

    function sprintf_parse(fmt) {
        if (sprintf_cache[fmt]) {
            return sprintf_cache[fmt]
        }

        var _fmt = fmt, match, parse_tree = [], arg_names = 0
        while (_fmt) {
            if ((match = re.text.exec(_fmt)) !== null) {
                parse_tree.push(match[0])
            }
            else if ((match = re.modulo.exec(_fmt)) !== null) {
                parse_tree.push('%')
            }
            else if ((match = re.placeholder.exec(_fmt)) !== null) {
                if (match[2]) {
                    arg_names |= 1
                    var field_list = [], replacement_field = match[2], field_match = []
                    if ((field_match = re.key.exec(replacement_field)) !== null) {
                        field_list.push(field_match[1])
                        while ((replacement_field = replacement_field.substring(field_match[0].length)) !== '') {
                            if ((field_match = re.key_access.exec(replacement_field)) !== null) {
                                field_list.push(field_match[1])
                            }
                            else if ((field_match = re.index_access.exec(replacement_field)) !== null) {
                                field_list.push(field_match[1])
                            }
                            else {
                                throw new SyntaxError('[sprintf] failed to parse named argument key')
                            }
                        }
                    }
                    else {
                        throw new SyntaxError('[sprintf] failed to parse named argument key')
                    }
                    match[2] = field_list
                }
                else {
                    arg_names |= 2
                }
                if (arg_names === 3) {
                    throw new Error('[sprintf] mixing positional and named placeholders is not (yet) supported')
                }

                parse_tree.push(
                    {
                        placeholder: match[0],
                        param_no:    match[1],
                        keys:        match[2],
                        sign:        match[3],
                        pad_char:    match[4],
                        align:       match[5],
                        width:       match[6],
                        precision:   match[7],
                        type:        match[8]
                    }
                )
            }
            else {
                throw new SyntaxError('[sprintf] unexpected placeholder')
            }
            _fmt = _fmt.substring(match[0].length)
        }
        return sprintf_cache[fmt] = parse_tree
    }

    /**
     * export to either browser or node.js
     */
    /* eslint-disable quote-props */
    if (typeof exports !== 'undefined') {
        exports['sprintf'] = sprintf
        exports['vsprintf'] = vsprintf
    }
    if (typeof window !== 'undefined') {
        window['sprintf'] = sprintf
        window['vsprintf'] = vsprintf

        if (typeof define === 'function' && define['amd']) {
            define(function() {
                return {
                    'sprintf': sprintf,
                    'vsprintf': vsprintf
                }
            })
        }
    }
    /* eslint-enable quote-props */
}(); // eslint-disable-line


if (!String.prototype.repeat) {
  String.prototype.repeat = function(count) {
    'use strict';
    if (this == null)
      throw new TypeError('can\'t convert ' + this + ' to object');

    var str = '' + this;
    // To convert string to integer.
    count = +count;
    // Check NaN
    if (count != count)
      count = 0;

    if (count < 0)
      throw new RangeError('repeat count must be non-negative');

    if (count == Infinity)
      throw new RangeError('repeat count must be less than infinity');

    count = Math.floor(count);
    if (str.length == 0 || count == 0)
      return '';

    // Ensuring count is a 31-bit integer allows us to heavily optimize the
    // main part. But anyway, most current (August 2014) browsers can't handle
    // strings 1 << 28 chars or longer, so:
    if (str.length * count >= 1 << 28)
      throw new RangeError('repeat count must not overflow maximum string size');

    var maxCount = str.length * count;
    count = Math.floor(Math.log(count) / Math.log(2));
    while (count) {
       str += str;
       count--;
    }
    str += str.substring(0, maxCount - str.length);
    return str;
  }
}

// the flatten() function built into the PostProcessor throws errors when trying to flattenan array of strings 
// (at least, it did when I tried flattening an aray containing exactly one string)
// here is an improved array-flattening function, courtesy of https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Array/flat
function flattenDeep(arr1) {
   return arr1.reduce(
        function(acc, val){return (Array.isArray(val) ? acc.concat(flattenDeep(val)) : acc.concat(val));}, 
        []
   );
}

// var sprintf = eval(fileGetContents(FileSystem.getCombinedPath(getConfigurationFolder(),"sprintf.min.js"))); 

//debugMode=true;
// tolerance = spatial(0.002, MM);
tolerance = 0.01;//spatial(0.001, IN);

minimumChordLength = spatial(0.01, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(180);
allowHelicalMoves = false;
allowedCircularPlanes = 0;  //undefined; // set to 0 to forbid any circular motion and to undefined to allow circular motion on any plane

// user-defined properties
properties = {
  //these properties have a built-in definition (i.e. title string and description string that appears in the UI to explain what the property does
  useG28: true, //changed to false as a hard-coded workaround for lack of property-setting ability in fusion 360's api //true, // disable to avoid G28 output for safe machine retracts - when disabled you must manually ensure safe retracts
  useM6: true, // disable to avoid M6 output - preload is also disabled when M6 is disabled
  preloadTool: false, // preloads next tool on tool change if any
  useRadius: true, // specifies that arcs should be output using the radius (R word) instead of the I, J, and K words.
  
  //these are my own custom properties, which have corresponding entries in the propertyDefinitions map to define how these properties will be presented to the user in the ui.
  useG43WithM6ForToolchanges: true, //if useM6 is true, then whenever we output an M6, we will immediately afterward output a G43 to enable the tool length offset for the newly selected tool.
  // commandToRunOnTerminate: "", //a command to run on the shell when the platform invokes onTerminate() (which means the gcode file has been written, and is now available to be moved copied, or ingested by another tool).  We will run this command in the directory of the gcode file.
  
  //hardcoding as a temporary hack:
  // commandToRunOnTerminate: "copy /Y \"$${getOutputPath()}\" \"c:\\users\\admin\\google drive\\kensho\\g code\\$${FileSystem.getFilename(getOutputPath())}\"", //a command to run on the shell when the platform invokes onTerminate() (which means the gcode file has been written, and is now available to be moved copied, or ingested by another tool).  We will run this command in the directory of the gcode file.
  commandToRunOnTerminate: "copy /Y \"${getOutputPath()}\" \"c:\\users\\admin\\google drive\\kensho\\g code\\${FileSystem.getFilename(getOutputPath())}\"", //a command to run on the shell when the platform invokes onTerminate() (which means the gcode file has been written, and is now available to be moved copied, or ingested by another tool).  We will run this command in the directory of the gcode file.

  feedrateMode: "movesPerTime"
};

propertyDefinitions = {
    useG43WithM6ForToolchanges: {
        type: 'boolean',
        title: 'useG43WithM6ForToolchanges',
        description: 'applicable when useM6 is true.  If set to true and if useM6 is true, then whenever we output an M6, we will immediately afterward output a G43 to enable the tool length offset for the newly selected tool.',
        group: undefined,
        presentation: "truefalse"
    },
    
    commandToRunOnTerminate: {
        type: 'string', // 'string' is not one of the valid types according to the validatePropertyDefinition() logic.  However, the ui does seem to accept a string when there is no propertyDefinition, so I am hoping that it will continue to accept a string when there is a property defintion.
        title: 'commandToRunOnTerminate',
        description: 
            "a command to run on the shell when the platform invokes onTerminate() (which means the gcode file has been written, and is now " + 
            "available to be moved copied, or ingested by another tool).  We will run this command in the directory of the gcode file.  " +
            " You can include the result of evaluating a javascript expression by enclosing the expression in curly brackets following a dollar sign (" + 
            " actually, it seems that you usually need two dollar signs because hsmworks seems to be interpretting a single dollar sign as special.  " + 
            "HSMworks converts two dollar signs into a single dollar sign before passing the string to the routine that does the evaluation of the javascript.).  " +
            "the expression will be evaluated in the context of the post processor.  " + "\n" 
            +
            "EXAMPLE (this will copy the output gcode file to an arbitrary location in the filesystem: " + "\n" +
            "copy /Y \"$${getOutputPath()}\" \"/my/arbitrary/destination/$${FileSystem.getFilename(getOutputPath())}\""
         ,
        group: undefined

    },

    feedrateMode: {
        type: 'enum',
        title: 'feedrateMode',
        description: 'specifies whether the gcode should use "inverse time" feedrate mode (i.e. moves per time) (a.k.a. G93) or the more usual feedrate mode (i.e. length per time) (a.k.a. G94)',
        group: undefined,
        values: [
            {id: "movesPerTime",  title: "inverse time feedrate mode (a.k.a. G93)", description: "test description 1"},
            {id: "lengthPerTime", title: "standard feedrate mode (a.k.a. G94)", description: "test description 2"},
            {id: "lengthPerRevolution", title: "feedrate is proportional to spindle speed (a.k.a. G95)", description: "test description 3"}
        ]
    }
};

// TCP Options: These values are passed as arguments to PostProcessor::optimizeMachineAngles2() and related functions.
const TCP_MODE__MAINTAIN_TOOL_TIP_POSITION                  = 0;
/* Tool Center Point mode "Maintain tool tip position (TCPM)."
 *    In this mode, the coordinates that are passed as arguments to the motion functions (onLinear, onRapid, etc.) are 
 *    the coordinates of the tip of the tool in the work frame.  This is not what we want.
 */ 

const TCP_MODE__MAP_TOOL_TIP_POSITION                       = 1;  
/* map tip mode "Map tool tip position."                      
 *    In this mode, the values that are passed as arguments to the motion functions (onLinear, onRapid, etc.) are 
 *    the coordinates of the tip in the machine frame.  This is what we want.	
 */

const TCP_MODE__MAP_TOOL_TIP_POSITION_ONLY_FOR_TABLE_AXES   = 2;  
/*  "Map tool tip position for machine axes in table only. "
**     
**/



const permittedCommentChars = " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,=_-:";

var mapCoolantTable = new Table(
  [9, 8, 7],
  {initial:COOLANT_OFF, force:true},
  "Invalid coolant mode"
);

//{ G-code variables and number formats
var nFormat                        =  createFormat({prefix:"N", decimals:0});
var gFormat                        =  createFormat({prefix:"G", decimals:1});
var mFormat                        =  createFormat({prefix:"M", decimals:0});
var hFormat                        =  createFormat({prefix:"H", decimals:0});
var pFormat                        =  createFormat({prefix:"P", decimals:(unit == MM ? 3 : 4), scale:0.5});
var param1Format                   =  createFormat({prefix:"P", decimals:7});  //this format spec is used for the argument that mach3 scripts called from gcode will read as Param1()
var param2Format                   =  createFormat({prefix:"Q", decimals:7});  //this format spec is used for the argument that mach3 scripts called from gcode will read as Param2()
var param3Format                   =  createFormat({prefix:"R", decimals:7});  //this format spec is used for the argument that mach3 scripts called from gcode will read as Param3()
var xyzFormat                      =  createFormat({decimals:(unit == MM ? 3 : 4), width:(unit == MM ? 8 : 7), zeropad:true, trim:false, trimLeadZero:false, forceSign:true, forceDecimal:true});
var rFormat                        =  xyzFormat; // radius
var abcFormat                      =  createFormat({decimals:3, width: 11, scale:DEG, zeropad:true, trim:false, trimLeadZero:false, forceSign:true, forceDecimal:true});
var lengthPerTimeFeedFormat        =  createFormat({decimals:(unit == MM ? 0 : 1), width:(unit == MM ? 7 : 5), zeropad:true, trim:false, trimLeadZero:false, forceSign:false, forceDecimal:true});
var inverseTimeFeedFormat          =  createFormat({decimals:2, width:10, zeropad:true, trim:false, trimLeadZero:false, forceSign:false, forceDecimal:true});
var feedFormat                     =  (properties.feedrateMode == "movesPerTime" ? inverseTimeFeedFormat : lengthPerTimeFeedFormat); 
var toolFormat                     =  createFormat({decimals:0});
var rpmFormat                      =  createFormat({decimals:0});
var secondsFormat                  =  createFormat({decimals:3, forceDecimal:true}); // seconds - range 0.001-99999.999
var millisecondsFormat             =  createFormat({decimals:0}); // milliseconds // range 1-9999
var taperFormat                    =  createFormat({decimals:1, scale:DEG});
                                      
var xOutput                        =  createVariable({prefix:"X"}, xyzFormat);
var yOutput                        =  createVariable({prefix:"Y"}, xyzFormat);
var zOutput                        = createVariable({onchange:function () {retracted = false;}, prefix:"Z"}, xyzFormat);
var aOutput                        =  createVariable({prefix:"A"}, abcFormat);
var bOutput                        =  createVariable({prefix:"B"}, abcFormat);
var cOutput                        =  createVariable({prefix:"C"}, abcFormat);
var feedOutput                     =  createVariable({prefix:"F"}, feedFormat);
var sOutput                        =  createVariable({prefix:"S", force:true}, rpmFormat);
var pOutput                        =  createVariable({}, pFormat);

// circular output
var iOutput = createReferenceVariable({prefix:"I", force:true}, xyzFormat);
var jOutput = createReferenceVariable({prefix:"J", force:true}, xyzFormat);
var kOutput = createReferenceVariable({prefix:"K", force:true}, xyzFormat);

var gMotionModal      = createModal({}, gFormat); // modal group 1 // G0-G3, ...
var velocityBlendingModeModal      = createModal({}, gFormat); // G64 (constant velocity mode) or G61 (exact stop)
var gPlaneModal       = createModal({onchange:function () {gMotionModal.reset();}}, gFormat); // modal group 2 // G17-19
var gAbsIncModal      = createModal({}, gFormat); // modal group 3 // G90-91
var gFeedModeModal    = createModal({}, gFormat); // modal group 5 // G93-94
var gUnitModal        = createModal({}, gFormat); // modal group 6 // G20-21
var gCycleModal       = createModal({}, gFormat); // modal group 9 // G81, ...
var gRetractModal     = createModal({}, gFormat); // modal group 10 // G98-99
//}


/**
  Writes the specified block.
  The last argument can, optionally, be an object instead of a string, in which case we will regard the 
  last argument as an options specifier. 
  At the moment, the only option that I care about is 'trailingComment'
  So, if the last argument is an object having a 'trailingComment' property,
  then we will append 'trailingComment' to the end of the line, with some special 
  spacing to ensure that the trailing comments tend to be line dup vertically, at one of 
  a few preferred "tab stops".  This will make the g-code easier (for humans) to read.
*/
function writeBlock() {
    var options;
    var words;
    //the special 'arguments' object is not a true array, so we cannot slice it. therefore,
    //let's convert it into a true array // see https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Functions/arguments
    var arguments_array = Array.prototype.slice.call(arguments);
    
    if(typeof arguments_array[arguments_array.length - 1] === 'object' && !Array.isArray(arguments_array[arguments_array.length - 1])){
        //if the last element of arguments_array is an object (and not an array)
        words = arguments_array.slice(0,-1); //set words to an array that has all but the last element of arguments
        options = arguments_array[arguments_array.length - 1];
    } else {
        words = arguments_array;
        options = {};
    }
    var preferredTabStops=[0,30,60,90,120]; //please make sure that preferredTabStops is ordered increasing.
    //at this point, we have extracted from arguments the following: 
    // >>> words -- the array of strings to be written to the output (to which we might append one more element -
    // the trailing comment padded with spaces, if specified by options)
    // >>> options -- an object, which might contain special options, specifically a property named 
    // 'trailingComment', which is some text that is to be included as a comment at the end of the line
    // padded with leading spaces to create nice aesthetic horizontal alignment in the g-code file.
    var minimumAllowedPaddingLength = 3; //we will ensure that there is always this many spaces between the end of the business logic string and the beginning of the comment
    
    
    if(options.hasOwnProperty('trailingComment')){
        // I am assuming that the effect of the writeWords() function (which we invoke below)
        // is simply to (treating its argument as an array of strings) join the strings 
        // with some delimiting string (which we can lookup by calling getWordSeparator())
        // therefore, we can predict the length of the string that writeWords() will write to the output g-code file.
        // I will call the meaningful, machine-readable part of the g-code line, the "businessString"
        
        log("words: " + JSON.stringify(words));
        // var lengthOfBusinessString = flatten(words).join(getWordSeparator()).length;
        var lengthOfBusinessString = flattenDeep(words).join(getWordSeparator()).length;
        //oops -- writeBlock is supposed to be able to accept arrays of strings as arguments (and will then flatten)
        
        var tabStop;
        //compute tabStop - the index (we are regarding the first character of the line as having index=0), within the string that is the output line, 
        // where we want to have the first 
        // character of the comment appear.
        // the idea is that we want to ensure that tabStop >= lengthOfBusinessString.
        // (actually, to enforce minimumAllowedPaddingLength, we want to ensure that tabStop >= lengthOfBusinessString + minimumAllowedPaddingLength)
        // if possible, we would like to have tabStop be one of (specifically: the smallest allowable)
        // values in preferredTabStops.
        tabStop = lengthOfBusinessString + minimumAllowedPaddingLength; //this is the default (worst-case) choice, which will obtain in case the business string is too long for any of our preferred tab stops to work.
        for(var i = 0; i<preferredTabStops.length; i++){
            if(preferredTabStops[i] >= lengthOfBusinessString + minimumAllowedPaddingLength){
                //hurray, we have found the first (which we assume means smallest)
                // value in preferredTabStops that satisfies our requirement that 
                // tabStop >= lengthOfBusinessString.
                tabStop = preferredTabStops[i];
                break;
            }
        }
        //append the trailing comment (padded with leading spaces, and then a comment character, and possibly stripped of illegal characters)
        // to words.
        words.push(
            " ".repeat(tabStop - lengthOfBusinessString) //leading padding characters
            + ";  "
            + options['trailingComment']
        );
        
        // if we add the trailing comment by appending another string to words, the writeWords() function will stick a delimiting string (getWordSeparator()) 
        // before the padded trailing comment.  However, we do not want this, because we have already dealt with all the padding logic explicitly above.
        // therefore, intead of appending the trailing comment as another element on the end of words, it might make sense to 
        // append it as a string to the last element of words, but I won't worry about that for now.
    }
    writeWords(words);
}

/**
  Output a comment.
*/
function writeComment(text) {
  writeln("(" + filterText(String(text).toUpperCase(), permittedCommentChars) + ")");
}

//{ ENTRY FUNCTIONS:
// These are the functions that HSMWorks invokes.

function onOpen() {
    
    // log("machineConfiguration.getMaximumFeedrate(): " + machineConfiguration.getMaximumFeedrate() + "\n");
    // log("machineConfiguration.getMaximumCuttingFeedrate(): " + machineConfiguration.getMaximumCuttingFeedrate() + "\n");
    // log("machineConfiguration.getFeedrateRatio(): " + machineConfiguration.getFeedrateRatio() + "\n");
    // log("machineConfiguration.getToolChangeTime(): " + machineConfiguration.getToolChangeTime() + "\n");
    // log("achineConfiguration.getMaximumSpindlePower(): " + machineConfiguration.getMaximumSpindlePower() + "\n");
    // log("machineConfiguration.getMaximumSpindleSpeed(): " + machineConfiguration.getMaximumSpindleSpeed() + "\n");

    // //*// machineConfiguration.setSingularity(
    // //*//     Boolean adjust, 
    // //*//     Integer method, 
    // //*//     Number cone, 
    // //*//     Number angle, 
    // //*//     Number tolerance, 
    // //*//     Number linearizationTolerance
    // //*// );

    // log("machineConfiguration.getSingularityAdjust(): " + machineConfiguration.getSingularityAdjust() + "\n");
    // log("machineConfiguration.getSingularityMethod(): " + machineConfiguration.getSingularityMethod() + "\n");
    // log("machineConfiguration.getSingularityCone(): " + machineConfiguration.getSingularityCone() + "\n");
    // log("machineConfiguration.getSingularityAngle(): " + machineConfiguration.getSingularityAngle() + "\n");
    // log("machineConfiguration.getSingularityTolerance(): " + machineConfiguration.getSingularityTolerance() + "\n");
    // log("machineConfiguration.getSingularityLinearizationTolerance(): " + machineConfiguration.getSingularityLinearizationTolerance() + "\n");
    // log("machineConfiguration.getRetractPlane(): " + machineConfiguration.getRetractPlane() + "\n");
    // log("machineConfiguration.getHomePositionX(): " + machineConfiguration.getHomePositionX() + "\n");
    // log("machineConfiguration.getHomePositionY(): " + machineConfiguration.getHomePositionY() + "\n");


    // for(var coolant=0; coolant<=256; coolant++){
        // log("machineConfiguration.isCoolantSupported(" + coolant + "): " + machineConfiguration.isCoolantSupported(coolant) + "\n");
    // }

    // error("ahoy");
   // writeln("properties.commandToRunOnTerminate: " + properties.commandToRunOnTerminate)
   machineConfiguration = new MachineConfiguration(createAxis({
            //actuator: Specifies that the actuator type (ie. either "linear" or "rotational"). The default is "rotational".
            actuator: 'rotational',
            
            //table: Specifies that the axis is located in the table or the head. The default is true for table.
            table: true,
            
            //axis: Specifies the axis vector as a 3-element array (e.g. "[0, 0, 1]"). This specifier is required.
            axis: [1,0,0],
            
            //offset: Specifies the axis offset as a 3-element array (e.g. "[0, 0, 25]"). The default is [0, 0, 0].
            offset: [0,0,0],
            
            //coordinate: Specifies the coordinate used in the ABC vectors (ie. "X", "Y", or "Z"). This specifier is required.
            // this naming is a bit confusing.  hsmworks frequently uses a class called Vector (which has properties "X", "Y", and "Z") 
            // to reperesent triples of real numbers.  the property names "X", "Y", and "Z" make sense when the triple of reals is 
            // a triple of cartesian coordinates.  However, when, as it does, HSMWorks uses the Vector class to represent triples of Euler angles,
            // the property names a "X", "Y", and "Z" still must be used to access an item in the triple.  
            //the 'coordinate' specifier tells HSMWorks which of the three properties of an instance of Vector that represents 
            // a triple of Euler angles should be used to store the angular coordinate for this axis.
            coordinate: "X",
            
            //cyclic: Specifies that the axis is cyclic. Only supported for rotational axes. Only used when a range is specified. The default is false.
            cyclic: true,
            
            //range: Specifies the angular range for the axis in degrees as a 2-element array (e.g. "[-120, 120]"). You can also specify a single number to create an axis for an aggregate. The default is unbound.
            //range: 
            
            //preference: Specifies the preferred angles (-1:negative angles, 0:don't care, and 1:positive angles). The default is don't care.
            preference:  0,
            
            //resolution: Specifies the resolution. In degrees for rotational actuator. The default is 0.
            resolution: 0
    }));
    
    machineConfiguration.setMilling(true);
    machineConfiguration.setTurning(true);
    machineConfiguration.setWire(false);
    // machineConfiguration.setJet(false); //threw an error:  Error: TypeError: machineConfiguration.setJet is not a function
    machineConfiguration.setToolChanger(true);
    machineConfiguration.setToolPreload(false);
    machineConfiguration.setNumberOfTools(99);

    // machineConfiguration.setMaximumToolLength(Number maximumToolLength);
    // machineConfiguration.setMaximumToolDiameter(Number maximumToolDiameter);
    // machineConfiguration.setMaximumToolWeight(Number maximumToolWeight);
    machineConfiguration.setMaximumFeedrate(15240); //corresponds to 600 inches per minute
    machineConfiguration.setMaximumCuttingFeedrate(15240);
    // machineConfiguration.setMaximumBlockProcessingSpeed(Integer maximumBlockProcessingSpeed);
    machineConfiguration.setNumberOfWorkOffsets(255);
    machineConfiguration.setFeedrateRatio(1);
    machineConfiguration.setToolChangeTime(30);
    // machineConfiguration.setDimensions(Vector dimensions);
    // machineConfiguration.setWidth(Number width);
    // machineConfiguration.setDepth(Number depth);
    // machineConfiguration.setHeight(Number height);
    // machineConfiguration.setWeight(Number weight);
    // machineConfiguration.setPartDimensions(Vector partDimensions);
    // machineConfiguration.setPartMaximumX(Number width);
    // machineConfiguration.setPartMaximumY(Number depth);
    // machineConfiguration.setPartMaximumZ(Number height);
    // machineConfiguration.setWeightCapacity(Number weightCapacity);
    machineConfiguration.setSpindleAxis(new Vector(0,0,1));
    // machineConfiguration.setSpindleDescription(String spindleDescription);
    machineConfiguration.setMaximumSpindlePower(2.238);
    machineConfiguration.setMaximumSpindleSpeed(24000);
    machineConfiguration.setCollectChuck("ER20");
        machineConfiguration.setSingularity(
            //Boolean adjust, 
            true,
            
            //Integer method, 
            2,
            
            //Number cone, 
            0.05235987755982989,
            
            //Number angle, 
            0.17453292519943295,
            
            //Number tolerance, 
            0.04,
            
            //Number linearizationTolerance
            0.04
        );
    machineConfiguration.setRetractPlane(254);
    machineConfiguration.setHomePositionX(0);
    machineConfiguration.setHomePositionY(0);
    machineConfiguration.setModel("Maverick");
    machineConfiguration.setDescription("Kensho's Legacy Maverick");
    machineConfiguration.setVendor("Legacy");
    // machineConfiguration.setVendorUrl(String vendorUrl)
    machineConfiguration.setControl("Mach3/Smoothstepper");
    machineConfiguration.setCoolantSupported(1, true);
    machineConfiguration.setRetractOnIndexing(true);
    machineConfiguration.setShortestAngularRotation(true);

       

  
  // map tip mode //in this mode, the coordinates that appear as numbers in the gcode are 
  // the coordinates of the tip in the machine frame.  This is what we want.	
  optimizeMachineAngles2(TCP_MODE__MAP_TOOL_TIP_POSITION); 
  
  
  if (!machineConfiguration.isMachineCoordinate(0)) {
    aOutput.disable();
	  //writeComment("A output is disabled");
  }
  if (!machineConfiguration.isMachineCoordinate(1)) {
    bOutput.disable();
		//writeComment("B output is disabled");
  }
  if (!machineConfiguration.isMachineCoordinate(2)) {
    cOutput.disable();
		//writeComment("C output is disabled");
  }
  

  if(programName || programComment) { //write program name
     if (programName) {
       writeComment(programName);
     }
     if (programComment) {
       writeComment(programComment);
     }
     writeln("");
  }

    writeln("; output path: " + getOutputPath());

  if ((machineConfiguration.getVendor() || machineConfiguration.getModel() || machineConfiguration.getDescription())) { // dump machine information
    writeComment(localize("Machine" + ":"));
    if (machineConfiguration.getVendor()) {
      writeComment("  " + localize("vendor") + ": " + machineConfiguration.getVendor());
    }
    if (machineConfiguration.getModel()) {
      writeComment("  " + localize("model") + ": " + machineConfiguration.getModel());
    }
    if (machineConfiguration.getDescription()) {
      writeComment("  " + localize("description") + ": "  + machineConfiguration.getDescription());
    }
    writeln("");
  }

  
  if (true) { // dump tool information
    writeComment("TOOL LIST: ");
    var zRanges = {};
    if (is3D()) {
      var numberOfSections = getNumberOfSections();
      for (var i = 0; i < numberOfSections; ++i) {
        var section = getSection(i);
        var zRange = section.getGlobalZRange();
        var tool = section.getTool();
        if (zRanges[tool.number]) {
          zRanges[tool.number].expandToRange(zRange);
        } else {
          zRanges[tool.number] = zRange;
        }
      }
    }

    var tools = getToolTable();
    if (tools.getNumberOfTools() > 0) {
      for (var i = 0; i < tools.getNumberOfTools(); ++i) {
        var tool = tools.getTool(i);
        var comment = "T" + toolFormat.format(tool.number) + "  " +
          "D=" + xyzFormat.format(tool.diameter) + " " +
          localize("CR") + "=" + xyzFormat.format(tool.cornerRadius);
        if ((tool.taperAngle > 0) && (tool.taperAngle < Math.PI)) {
          comment += " " + localize("TAPER") + "=" + taperFormat.format(tool.taperAngle) + localize("deg");
        }
        if (zRanges[tool.number]) {
          comment += " - " + localize("ZMIN") + "=" + xyzFormat.format(zRanges[tool.number].getMinimum());
        }
        comment += " - " + getToolTypeName(tool.type);
        writeComment(comment);
      }
    }
    writeln("");
  }
  
  // if (true) {// check for duplicate tool number
  //I have disabled checking for duplicate tool numbers because it was triggering an error when I wanted to
  // have the same tool number assigned to a threading tool and a chamfering tool which are, in reality, the same tool, but
  // the logic below thinks that they are diofferent and would throw an error.
  if (false) {// check for duplicate tool number
    for (var i = 0; i < getNumberOfSections(); ++i) {
      var sectioni = getSection(i);
      var tooli = sectioni.getTool();
      for (var j = i + 1; j < getNumberOfSections(); ++j) {
        var sectionj = getSection(j);
        var toolj = sectionj.getTool();
        if (tooli.number == toolj.number) {
          if (xyzFormat.areDifferent(tooli.diameter, toolj.diameter) ||
              xyzFormat.areDifferent(tooli.cornerRadius, toolj.cornerRadius) ||
              abcFormat.areDifferent(tooli.taperAngle, toolj.taperAngle) ||
              (tooli.numberOfFlutes != toolj.numberOfFlutes)) {
            error(
              subst(
                localize("Using the same tool number for different cutter geometry for operation '%1' and '%2'."),
                sectioni.hasParameter("operation-comment") ? sectioni.getParameter("operation-comment") : ("#" + (i + 1)),
                sectionj.hasParameter("operation-comment") ? sectionj.getParameter("operation-comment") : ("#" + (j + 1))
              )
            );
            return;
          }
        }
      }
    }
  }

  // set initial modes
  writeComment("initial modes:");
  gAbsIncModal.reset();   writeBlock(gAbsIncModal.format(90), {trailingComment: "position mode: absolute"});
  gFeedModeModal.reset(); writeBlock(gFeedModeModal.format(94), {trailingComment: "feedrate mode: length per time"});
  writeBlock(gFormat.format(91.1), {trailingComment: "arc center mode: incremental"});
  writeBlock(gFormat.format(40), {trailingComment: "cancel cutter radius compensation"});
  cancelToolHeightOffset();
  gPlaneModal.reset(); writeBlock(gPlaneModal.format(17), {trailingComment: "plane for circular moves: XY plane"});
  velocityBlendingModeModal.reset(); writeBlock(velocityBlendingModeModal.format(64), {trailingComment: "constant velocity mode"});
  setUnit(unit);
}


function onComment(message) {
  var comments = String(message).split(";");
  for (comment in comments) {
    writeComment(comments[comment]);
  }
}

function onSection() {
    writeln("");
    var sectionHeader = "(***** SECTION " + (getCurrentSectionId() + 1) + " OF " + getNumberOfSections() + " *****)";
    log(sectionHeader);
    writeln(sectionHeader + " " + doNothingOpener);
    var sectionParameters = getSectionParameters(currentSection);
    if (sectionParameters["operation-comment"]) {writeComment(sectionParameters["operation-comment"]);}
    
    //look for a magically-formatted string in the operation-comment and take special action accordingly
    var matches = sectionParameters["operation-comment"].match("{override=([^}]*)}");
    if(matches && matches.length >= 2){
        eval(matches[1]);
        skipRemainingSection();
        return;
    }
    
    modifyToolOrientationInPostProcessing = Boolean(sectionParameters["operation-comment"] && ("modifyToolOrientationInPostProcessing" in sectionParameters["operation-comment"].split(/\W+/)));
    
    // getRemainingOrientation_UnitTest(machineConfiguration);
    
    // logDebug("sectionParameters: " + sectionParameters);
    // logDebug("sectionParameters: " + Object.keys(sectionParameters));
    logDebug("sectionParameters: ");
    Object.keys(sectionParameters).map(function(key){logDebug(key + ": " + sectionParameters[key], 1);});

    
    logDebug("currentSection.workPlane: " + currentSection.workPlane);
    logDebug("currentSection.getWorkPlane(): " + currentSection.getWorkPlane());
    logDebug("currentSection.getChannel(): " + currentSection.getChannel());
    logDebug("currentSection.getNumberOfRecords(): " + currentSection.getNumberOfRecords());
    logDebug("currentSection.getInitialPosition(): " + currentSection.getInitialPosition());
    try{logDebug("currentSection.getGlobalInitialToolAxis(): " + currentSection.getGlobalInitialToolAxis())} catch(e){logDebug("currentSection.getGlobalInitialToolAxis() threw an exception: " + e);};
    try{logDebug("currentSection.getInitialToolAxis(): " + currentSection.getInitialToolAxis())} catch(e){logDebug("currentSection.getInitialToolAxis() threw an exception: " + e);};
    try{logDebug("currentSection.getInitialToolAxisABC(): " + currentSection.getInitialToolAxisABC())} catch(e){logDebug("currentSection.getInitialToolAxisABC() threw an exception: " + e);};
    try{logDebug("currentSection.getGlobalFinalToolAxis(): " + currentSection.getGlobalFinalToolAxis())} catch(e){logDebug("currentSection.getGlobalFinalToolAxis() threw an exception: " + e);};
    try{logDebug("currentSection.getFinalToolAxis(): " + currentSection.getFinalToolAxis())} catch(e){logDebug("currentSection.getFinalToolAxis() threw an exception: " + e);};
    try{logDebug("currentSection.getFinalToolAxisABC(): " + currentSection.getFinalToolAxisABC())} catch(e){logDebug("currentSection.getFinalToolAxisABC() threw an exception: " + e);};
    logDebug("getMachineConfiguration().getPosition(getCurrentPosition(), getCurrentDirection()): " + getMachineConfiguration().getPosition(getCurrentPosition(), getCurrentDirection()));
    logDebug("getMachineConfiguration().getDirection(getCurrentDirection()): " + getMachineConfiguration().getDirection(getCurrentDirection()) + " (length: " + norm(getMachineConfiguration().getDirection(getCurrentDirection())) + ")");
    logDebug("currentSection.isOptimizedForMachine(): " + currentSection.isOptimizedForMachine());
    logDebug("currentSection.getOptimizedTCPMode(): " + currentSection.getOptimizedTCPMode());
    logDebug("currentSection.getWorkPlane(): " + currentSection.getWorkPlane());
    try{logDebug("currentSection.getUpperToolAxisABC(): " + currentSection.getUpperToolAxisABC());} catch(e){logDebug("currentSection.getUpperToolAxisABC() threw an exception: " + e);}
    try{logDebug("currentSection.getLowerToolAxisABC(): " + currentSection.getLowerToolAxisABC());} catch(e){logDebug("currentSection.getLowerToolAxisABC() threw an exception: " + e);}
    // It seems that section::getUpperToolAxisABC() and section::getUpperToolAxisABC() returns the maximum and minimum values, respectively, of the direction (as retruned by getCurrentDirection()) attained in the section.
    log("currentSection.workPlane: " + currentSection.workPlane);
    // log(dumpObjectToString(xyzFormat));
    // // log(createFormat);
    // // log(Format);
    // log(xyzFormat);
    // log(dumpObjectToString(FormatNumber));
    // logDebug("currentSection.getFinalPosition()(): " + currentSection.getFinalPosition()());
    // logDebug("currentSection.getNumberOfSegments()()(): " + currentSection.getNumberOfSegments()()());

    // log((745).toFixed(6));
    // log((745).toFixed(4));
    // log(new Vector(11,22,33));
    // log(dumpObjectToString(new Vector(11,22,33)));
    // log(dumpObjectToString(Vector));
    // log(coordinateListToString([1,2,3,4,5,6]));
    // log(coordinateListToString([undefined,undefined,undefined,undefined,undefined,undefined]));
    // log(coordinateListToString(lastCoordinates));
    // log(coordinateListToString(lastCoordinates));
    // log([undefined,1,2,3,undefined,undefined].map(function(v,k){return String(k) + "---" + String(v);}));
    // log(new Vector(11,22,33));
    // log(new Vector([55,66,77]));
    // var sprintf = eval(fileGetContents(FileSystem.getCombinedPath(getConfigurationFolder(),"sprintf.min.js"))); 
    // function(){"use strict";var g={not_string:/[^s]/,not_bool:/[^t]/,not_type:/[^T]/,not_primitive:/[^v]/,number:/[diefg]/,numeric_arg:/[bcdiefguxX]/,json:/[j]/,not_json:/[^j]/,text:/^[^\x25]+/,modulo:/^\x25{2}/,placeholder:/^\x25(?:([1-9]\d*)\$|\(([^)]+)\))?(\+)?(0|'[^$])?(-)?(\d+)?(?:\.(\d+))?([b-gijostTuvxX])/,key:/^([a-z_][a-z_\d]*)/i,key_access:/^\.([a-z_][a-z_\d]*)/i,index_access:/^\[(\d+)\]/,sign:/^[+-]/};function y(e){return function(e,t){var r,n,i,s,a,o,p,c,l,u=1,f=e.length,d="";for(n=0;n<f;n++)if("string"==typeof e[n])d+=e[n];else if("object"==typeof e[n]){if((s=e[n]).keys)for(r=t[u],i=0;i<s.keys.length;i++){if(null==r)throw new Error(y('[sprintf] Cannot access property "%s" of undefined value "%s"',s.keys[i],s.keys[i-1]));r=r[s.keys[i]]}else r=s.param_no?t[s.param_no]:t[u++];if(g.not_type.test(s.type)&&g.not_primitive.test(s.type)&&r instanceof Function&&(r=r()),g.numeric_arg.test(s.type)&&"number"!=typeof r&&isNaN(r))throw new TypeError(y("[sprintf] expecting number but found %T",r));switch(g.number.test(s.type)&&(c=0<=r),s.type){case"b":r=parseInt(r,10).toString(2);break;case"c":r=String.fromCharCode(parseInt(r,10));break;case"d":case"i":r=parseInt(r,10);break;case"j":r=JSON.stringify(r,null,s.width?parseInt(s.width):0);break;case"e":r=s.precision?parseFloat(r).toExponential(s.precision):parseFloat(r).toExponential();break;case"f":r=s.precision?parseFloat(r).toFixed(s.precision):parseFloat(r);break;case"g":r=s.precision?String(Number(r.toPrecision(s.precision))):parseFloat(r);break;case"o":r=(parseInt(r,10)>>>0).toString(8);break;case"s":r=String(r),r=s.precision?r.substring(0,s.precision):r;break;case"t":r=String(!!r),r=s.precision?r.substring(0,s.precision):r;break;case"T":r=Object.prototype.toString.call(r).slice(8,-1).toLowerCase(),r=s.precision?r.substring(0,s.precision):r;break;case"u":r=parseInt(r,10)>>>0;break;case"v":r=r.valueOf(),r=s.precision?r.substring(0,s.precision):r;break;case"x":r=(parseInt(r,10)>>>0).toString(16);break;case"X":r=(parseInt(r,10)>>>0).toString(16).toUpperCase()}g.json.test(s.type)?d+=r:(!g.number.test(s.type)||c&&!s.sign?l="":(l=c?"+":"-",r=r.toString().replace(g.sign,"")),o=s.pad_char?"0"===s.pad_char?"0":s.pad_char.charAt(1):" ",p=s.width-(l+r).length,a=s.width&&0<p?o.repeat(p):"",d+=s.align?l+r+a:"0"===o?l+a+r:a+l+r)}return d}(function(e){if(p[e])return p[e];var t,r=e,n=[],i=0;for(;r;){if(null!==(t=g.text.exec(r)))n.push(t[0]);else if(null!==(t=g.modulo.exec(r)))n.push("%");else{if(null===(t=g.placeholder.exec(r)))throw new SyntaxError("[sprintf] unexpected placeholder");if(t[2]){i|=1;var s=[],a=t[2],o=[];if(null===(o=g.key.exec(a)))throw new SyntaxError("[sprintf] failed to parse named argument key");for(s.push(o[1]);""!==(a=a.substring(o[0].length));)if(null!==(o=g.key_access.exec(a)))s.push(o[1]);else{if(null===(o=g.index_access.exec(a)))throw new SyntaxError("[sprintf] failed to parse named argument key");s.push(o[1])}t[2]=s}else i|=2;if(3===i)throw new Error("[sprintf] mixing positional and named placeholders is not (yet) supported");n.push({placeholder:t[0],param_no:t[1],keys:t[2],sign:t[3],pad_char:t[4],align:t[5],width:t[6],precision:t[7],type:t[8]})}r=r.substring(t[0].length)}return p[e]=n}(e),arguments)}function e(e,t){return y.apply(null,[e].concat(t||[]))}var p=Object.create(null);"undefined"!=typeof exports&&(exports.sprintf=y,exports.vsprintf=e),"undefined"!=typeof window&&(window.sprintf=y,window.vsprintf=e,"function"==typeof define&&define.amd&&define(function(){return{sprintf:y,vsprintf:e}}))}();
    // log(define);
    // log(sprintf);
    // log(sprintf.sprintf('%2$s %3$s a %1$s', 'cracker', 'Polly', 'wants'));
    // log(getPostProcessorFolder());
    // log(getPostProcessorPath());
    // log(getConfigurationFolder());
    // log(fileGetContents(FileSystem.getCombinedPath(getConfigurationFolder(),"sprintf.min.js")));

    // for(recordNumber=0; recordNumber<currentSection.getNumberOfRecords(); recordNumber++){
        // try{
            // var thisRecord = currentSection.getRecord(recordNumber);
            // logDebug("record " + recordNumber + ":");
            // logDebug("\t" + "getType(): " + thisRecord.getType());
            // logDebug("\t" + "getCategories(): " + thisRecord.getCategories());
            // logDebug("\t" + "getParameterName(): " + thisRecord.getParameterName());
            // logDebug("\t" + "getParameterValue(): " + thisRecord.getParameterValue());
            // logDebug("\t" + "isParameter(): " + thisRecord.isParameter());
            // logDebug("\t" + "isValid(): " + thisRecord.isValid());
        // } catch(e) {
            // logDebug("encountered an exception while looking at record " + recordNumber + ": " + e);
        // }
    // }

    var weShouldInsertAToolCall = isFirstSection() || currentSection.getForceToolChange() || (tool.number != getPreviousSection().getTool().number);
    var weAreDealingWithANewWorkOffset = isFirstSection() || (getPreviousSection().workOffset != currentSection.workOffset); // work offset changes
    var weAreDealingWithANewWorkPlane = isFirstSection() || !isSameDirection(getPreviousSection().getGlobalFinalToolAxis(), currentSection.getGlobalInitialToolAxis());

    setWorkOffset(currentSection.workOffset);

    //RETRACT TO A SAFE Z LEVEL, IF NECESSARY
    // This part is a bit obosolete and could probably use to be deleted or refactored.
    if (weShouldInsertAToolCall || weAreDealingWithANewWorkOffset || weAreDealingWithANewWorkPlane) {writeRetract(Z); }

    //CHANGE THE TOOL, IF NECESSARY.
    if (weShouldInsertAToolCall) {
        forceWorkPlane();
        onCommand(COMMAND_STOP_SPINDLE);
        onCommand(COMMAND_COOLANT_OFF);
        if (tool.number > 256) { warning(localize("Tool number exceeds maximum value."));  }    
        var words = [];
        var comments = [];
        words.push("T" + toolFormat.format(tool.number)); comments.push("the current tool is now tool " + tool.number);
        if (properties.useM6) { words.push(mFormat.format(6));  comments.push("please perform a  tool change operation."); }
        writeBlock(words, {trailingComment: comments.join("  ")});
        if(properties.useM6 && properties.useG43WithM6ForToolchanges){setToolLengthOffset(tool.lengthOffset);}
        if (tool.comment) {writeComment(tool.comment);}
        if (properties.preloadTool && properties.useM6) {
            var nextTool = getNextTool(tool.number);
            if (nextTool) {
                writeBlock("T" + toolFormat.format(nextTool.number));
            } else {
                // preload first tool
                var firstToolNumber = getSection(0).getTool().number;
                if (tool.number != firstToolNumber) {writeBlock("T" + toolFormat.format(firstToolNumber));}
            }
        }
    }

    //turn on THE SPINDLE 
    onSpindleSpeed(tool.spindleRPM);
    onCommand(COMMAND_START_SPINDLE);
    
    //turn on coolant, if necessary
    var c = mapCoolantTable.lookup(tool.coolant);
    if (c) {writeBlock(mFormat.format(c), {trailingComment: "turn on coolant"});} 
    else {warning(localize("Coolant not supported."));}

    xOutput.reset();
    yOutput.reset();
    zOutput.reset();
    aOutput.reset();
    bOutput.reset();
    cOutput.reset();
    feedOutput.reset();
    gMotionModal.reset();
    
    velocityBlendingModeModal.reset(); writeBlock(velocityBlendingModeModal.format(64),  {trailingComment: "constant velocity mode"});

    //move the machine safely to the initial position/angular state of this section

    //first, handle the angular axes:
    // writeBlock("M202",  {trailingComment: "add a multiple of 360 to the G92 offset of the rotary coordinate")); //anti-windup reset of rotary coordinate.
    if (machineConfiguration.isMultiAxisConfiguration()) {
        var initialABC = ( currentSection.isMultiAxis() ? currentSection.getInitialToolAxisABC() : machineConfiguration.getABC(currentSection.workPlane) );
        //this is the triple of angular coordinates that HSMWorks will pass as an argumnet on the first motion handler call.
        
        //we want to set angularCoordinateOffset so that
        // (initialABC + angularCoordinateOffset)  (which is where the first moveTo() will attempt to drive the machine
        //  is as close as possible to the current angular coordinates (while still being equiavalent mod 2*PI).
        
        angularCoordinateOffset = vectorToArray(
            Vector.diff(
                new Vector(getEquivalentTripleOfAngularCoordinatesClosestToCurrentAngularCoordinates(initialABC)),
                initialABC
            )
        );
        
        log("initialABC: " + initialABC);
        log("angularCoordinateOffset: " + angularCoordinateOffset);
        
        // The two arguments to Vector.diff() above are equivalent to one another mod 2*PI, which means Vector.diff will be equivalent to zero mod 2*PI,
        // which is what we want.
        moveTo([undefined, undefined, undefined].concat(vectorToArray(initialABC)));
        // // set working plane after datum shift
        // if (currentSection.isMultiAxis()) {
            // forceWorkPlane();
            // cancelTransformation();
            // setWorkPlane(new Vector(0, 0, 0));
        // } else {
            // forceWorkPlane(); 
            // //added the above "forceWorkPlane();" line as a hack to work around the problem that happens when you have 
            // // a >3-axis section that
            // // leaves the angular coordinates at something other than zero, and then you have a 3-axis section whose
            // // work plane machine angles are zero.  In this case, the call to setWorkPlane() that happens as part of the 
            // // onSection() call for the >3 axis section causes currentWorkPlaneABC to be set to (0,0,0).
            // // When setWorkPlane() is called in the onSection() call for the 3-axis section, currentWorkPlaneABC is still (0,0,0),
            // // and this causes setWorkPlane() to conclude (erroneously) that no motion needs to occur in the rotary axes.
            // //the newer version of the out-of-the-box mach3 post-processor from hsmworks seems to have corrected this flaw
            // // as part of it's defineWorkPlane() function (which is invoked on line 879, and in turn calls forceWorkPlane().
            // //my hack is to include forceWorkPlane() here so that forceWorkPlane() is always called befopre calling setWorkPlane().
            // // The disconnect between the 3-axis world and the >3 axis world creates major headaches, of which this whole setWorkPlane() 
            // // business is one.
            // // The drawback of always doing forceWorkPlane() is that the setWoirkPlane() operation will always feel that it needs to command some motion 
            // // and will therefore always perform a writeRetract, which might not be necessary if we were thinking carefully.  I think the answer is to
            // // to track the rotary axes coordinates carefully, so we know where we are (in all six degrees of freedom, and therefore can easily 
            // // determine whether to move.
            // setWorkPlane(getWorkPlaneMachineABC(currentSection.workPlane));
            
        // }
        
    } else { 
        // pure 3D
        var remaining = currentSection.workPlane;
        if (!isSameDirection(remaining.forward, new Vector(0, 0, 1))) {
            error(localize("Tool orientation is not supported."));
            return;
        }
        setRotation(remaining);
    }

    //then handle the cartesian axes
    var initialPosition = getFramePosition(currentSection.getInitialPosition());
    
    // if we have retracted the z axis to a safe height (which we would have done with a  G28 call) or if 
    // we know the current z coordinate and that coordinate is higher than the z coordinate of the initial position 
    // of this section's toolpath, then we are satisfied that we are already as retracted as we need to be.
    // Otherwise, we should drive the z axis to the z coordinate of the intitial position of this section's toolpath.
    if (!(retracted || (getCurrentCoordinates()[2] != undefined && getCurrentCoordinates()[2] >= initialPosition.z) )) {
      // if we have not retracted the z axis (which would happen in the case where properties.useG28 is false), then the next best thing is to 
      // drive the z axis to the z coordinate of the initial position of this section
      moveTo([undefined,undefined,initialPosition.z]);
    }
    //move to the initial xy position
    writeln("( now driving the machine's cartesian axes to the coordinates of the initial position of this section's toolpath, in preparation for commencing this section's toolpath.) ");
    moveTo([ initialPosition.x,  initialPosition.y,  undefined          ]);
    moveTo([ initialPosition.x,  initialPosition.y,  initialPosition.z  ]); 
    writeln("( we have now driven the cartesian axes to the correct initial position for this section's toolpath. ) ");
    // you might think that, because the first motion handler will take us to the initial position, that we do not need to 
    // have the above moveTo to take us to the x,y, and z coordinates of the first position (in other words, we could have just moved to the x and y coordinates 
    // of the first position and then let the first motion handler call take us to the correct z.
    //However, I want to have the moveTo() above with all three coordinates speciifed to bve sure that we know all coordinates (including the current z coordinate)
    // when the first motion handler call occurs so that we can do inverse time feed rate mode in that first motion handler call if desired.
    // in the case where we had retracted above using G28, we would not know the current z coordinate.  To handle this case is the main reason that 
    // I include the above call to moveTo with X, Y, and Z coordinates specified.

}

// m s expected to be a MachineConfiguration
function getRemainingOrientation_UnitTest(m){
    var passes=true;
    var failingCases=[];
    var numberOfTrials = 100;
    for(var i=0; i<numberOfTrials; i++){
        //construct Q and W -- two arbitrary invertible matrices.
        // var Q = getRandomUnitaryMatrix();
        var W = getRandomUnitaryMatrix();
         
        var theta = 6.0*(-1.0 + 2.0*Math.random())*Math.PI*Math.random(); //allowing the random angle to be in the range (-6*Pi, 6*Pi), just to spice things up.
        var v = getRandomNonzeroVector().getNormalized();
        var Q = new Matrix(v, theta);
        var inverseOfQ = new Matrix(v, -theta);
        // log(matrixTolerantEquals(W.multiply(inverseOfW), new Matrix()));

        var P = m.getOrientation(m.getABC(Q));
        var R = m.getRemainingOrientation(m.getABC(P),W);
        
        
        
        log("trial " + (i+1) + ": " );
        log("W is " + (matrixTolerantEquals(W.multiply(W.getTransposed()), new Matrix())  ? "" : "not ") + "unitary.");
        
        log("\t" + "Q: " + Q);
        log("\t" + "m.getABC(Q): " + m.getABC(Q));
        log("\t" + "m.getOrientation(m.getABC(Q)): " + (matrixTolerantEquals(Q, m.getOrientation(m.getABC(Q))) ? "Q" : "something other than Q: " + m.getOrientation(m.getABC(Q))));
        // log(matrixTolerantEquals(Q, m.getOrientation(m.getABC(Q))));
        
        
        log("\t" + "P: " + P);
        log("\t" + "m.getABC(P): " + m.getABC(P));
        log("\t" + "m.getOrientation(m.getABC(P)): " + (matrixTolerantEquals(P, m.getOrientation(m.getABC(P))) ? "P" : "something other than P: " + m.getOrientation(m.getABC(P))));
        // log(matrixTolerantEquals(P, m.getOrientation(m.getABC(P))));
        
        
        
        log("\t" + "W: " + W);
        log("\t" + "R: " + R);
        log("");
        
        
        
        if(!matrixTolerantEquals(P.multiply(R), W)){
            passes=false;
            failingCases.push({"Q":Q, "W":W});
        };
    }
    log("the unit test passed " + (numberOfTrials - failingCases.length)  + " out of " + numberOfTrials + " trials.");
    return passes;
}

function getRandomNonzeroVector(minAllowedEntry, maxAllowedEntry){
    if(typeof(minAllowedEntry) == "undefined"){minAllowedEntry = -100.0;}
    if(typeof(maxAllowedEntry) == "undefined"){maxAllowedEntry =  100.0;}
    var x;
    
    do{
        x = new Vector(
            minAllowedEntry + (maxAllowedEntry - minAllowedEntry)*Math.random(),
            minAllowedEntry + (maxAllowedEntry - minAllowedEntry)*Math.random(),
            minAllowedEntry + (maxAllowedEntry - minAllowedEntry)*Math.random()
        );
    } while (x.isZero());
   
    return x;
}

function getRandomUnitaryMatrix(){
    var randomAngle = 6.0*(-1.0 + 2.0*Math.random())*Math.PI*Math.random(); //allowing the random angle to be in the range (-6*Pi, 6*Pi), just to spice things up.
    return new Matrix(getRandomNonzeroVector().getNormalized(), randomAngle);
}


function onDwell(seconds) {
  if (seconds > 99999.999) {
    warning(localize("Dwelling time is out of range."));
  }
  if (true || properties.dwellInSeconds) {
    writeBlock(gFormat.format(4), "P" + secondsFormat.format(seconds));
  } else {
    milliseconds = clamp(1, seconds * 1000, 99999999);
    writeBlock(gFormat.format(4), "P" + millisecondsFormat.format(milliseconds));
  }
}

function onSpindleSpeed(spindleSpeed) {
  writeBlock(sOutput.format(spindleSpeed),  {trailingComment: "set spindle speed to " + spindleSpeed + " RPM"});
}

function onCycle() {
  writeBlock(gPlaneModal.format(17));
}

function onCyclePoint(x, y, z) {
  if (isFirstCyclePoint()) {
    repositionToCycleClearance(cycle, x, y, z);
    
    // return to initial Z which is clearance plane and set absolute mode

    var F = cycle.feedrate;
    var P = (cycle.dwell == 0) ? 0 : cycle.dwell; // in seconds

    switch (cycleType) {
    case "drilling":
      writeBlock(
        gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(81),
        getCommonCycle(x, y, z, cycle.retract),
        feedOutput.format(F)
      );
      break;
    case "counter-boring":
      if (P > 0) {
        writeBlock(
          gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(82),
          getCommonCycle(x, y, z, cycle.retract),
          "P" + secondsFormat.format(P),
          feedOutput.format(F)
        );
      } else {
        writeBlock(
          gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(81),
          getCommonCycle(x, y, z, cycle.retract),
          feedOutput.format(F)
        );
      }
      break;
    case "chip-breaking":
      // cycle.accumulatedDepth is ignored
      if (P > 0) {
        expandCyclePoint(x, y, z);
      } else {
        writeBlock(
          gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(73),
          getCommonCycle(x, y, z, cycle.retract),
          "Q" + xyzFormat.format(cycle.incrementalDepth),
          feedOutput.format(F)
        );
      }
      break;
    case "deep-drilling":
      if (P > 0) {
        expandCyclePoint(x, y, z);
      } else {
        writeBlock(
          gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(83),
          getCommonCycle(x, y, z, cycle.retract),
          "Q" + xyzFormat.format(cycle.incrementalDepth),
          // conditional(P > 0, "P" + secondsFormat.format(P)),
          feedOutput.format(F)
        );
      }
      break;
    case "tapping":
      if (tool.type == TOOL_TAP_LEFT_HAND) {
        expandCyclePoint(x, y, z);
      } else {
        if (!F) {
          F = tool.getTappingFeedrate();
        }
        writeBlock(mFormat.format(29), sOutput.format(tool.spindleRPM));
        writeBlock(
          gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(84),
          getCommonCycle(x, y, z, cycle.retract),
          feedOutput.format(F)
        );
      }
      break;
    case "left-tapping":
      expandCyclePoint(x, y, z);
      break;
    case "right-tapping":
      if (!F) {
        F = tool.getTappingFeedrate();
      }
      writeBlock(mFormat.format(29), sOutput.format(tool.spindleRPM));
      writeBlock(
        gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(84),
        getCommonCycle(x, y, z, cycle.retract),
        feedOutput.format(F)
      );
      break;
    case "fine-boring":
      writeBlock(
        gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(76),
        getCommonCycle(x, y, z, cycle.retract),
        "P" + secondsFormat.format(P),
        "Q" + xyzFormat.format(cycle.shift),
        feedOutput.format(F)
      );
      break;
    case "back-boring":
      var dx = (gPlaneModal.getCurrent() == 19) ? cycle.backBoreDistance : 0;
      var dy = (gPlaneModal.getCurrent() == 18) ? cycle.backBoreDistance : 0;
      var dz = (gPlaneModal.getCurrent() == 17) ? cycle.backBoreDistance : 0;
      writeBlock(
        gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(87),
        getCommonCycle(x - dx, y - dy, z - dz, cycle.bottom),
        "I" + xyzFormat.format(cycle.shift),
        "J" + xyzFormat.format(0),
        "P" + secondsFormat.format(P),
        feedOutput.format(F)
      );
      break;
    case "reaming":
      if (P > 0) {
        writeBlock(
          gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(89),
          getCommonCycle(x, y, z, cycle.retract),
          "P" + secondsFormat.format(P),
          feedOutput.format(F)
        );
      } else {
        writeBlock(
          gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(85),
          getCommonCycle(x, y, z, cycle.retract),
          feedOutput.format(F)
        );
      }
      break;
    case "stop-boring":
      writeBlock(
        gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(86),
        getCommonCycle(x, y, z, cycle.retract),
        "P" + secondsFormat.format(P),
        feedOutput.format(F)
      );
      break;
    case "manual-boring":
      writeBlock(
        gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(88),
        getCommonCycle(x, y, z, cycle.retract),
        "P" + secondsFormat.format(P),
        feedOutput.format(F)
      );
      break;
    case "boring":
      if (P > 0) {
        writeBlock(
          gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(89),
          getCommonCycle(x, y, z, cycle.retract),
          "P" + secondsFormat.format(P),
          feedOutput.format(F)
        );
      } else {
        writeBlock(
          gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(85),
          getCommonCycle(x, y, z, cycle.retract),
          feedOutput.format(F)
        );
      }
      break;
    default:
      expandCyclePoint(x, y, z);
    }
  } else {
    if (cycleExpanded) {
      expandCyclePoint(x, y, z);
    } else {
      writeBlock(xOutput.format(x), yOutput.format(y));
    }
  }
}

function onCycleEnd() {
  if (!cycleExpanded) {
    writeBlock(gCycleModal.format(80));
    zOutput.reset();
  }
}

function onRadiusCompensation() {
  pendingRadiusCompensation = radiusCompensation;
}

function onRewindMachine() {
    if(debugging) {
        writeln("onRewindMachine() was called.");
   }
}



function getEquivalentTripleOfAngularCoordinatesClosestToCurrentAngularCoordinates(abc){
    return vectorToArray(
        machineConfiguration.remapToABC(
            abc,
            (
                lastCoordinates.slice(3).every(function(x){return typeof(x) !== 'undefined';})
                ?
                new Vector(lastCoordinates.slice(3))
                :
                new Vector(0,0,0)
            )
        )
    );
    // machineConfiguration.remapToABC(q,w) takes a triple of angles q 
    // and returns a new triple of angles where each returned angle is equal mod 2*PI to the 
    // corresponding angle in q, and is within PI of the corresponding  angle in w.
    // for "multi-axis" (i.e. 4-axis or 5-axis) sections, currentSection.workPlane always returns the identity matrix.
}    

function onRapid    (_x, _y, _z                    ) { moveTo([_x,_y,_z].concat(vectorToArray(machineConfiguration.getABC(currentSection.workPlane))),   {nameOfCallback:"onRapid"                   });     }
function onLinear   (_x, _y, _z,              feed ) { moveTo([_x,_y,_z].concat(vectorToArray(machineConfiguration.getABC(currentSection.workPlane))),   {nameOfCallback:"onLinear",   feedrate:feed });     }
function onRapid5D  (_x, _y, _z, _a, _b, _c        ) { moveTo([_x,_y,_z,_a,_b,_c],                                                        {nameOfCallback:"onRapid5D"                 });     }
function onLinear5D (_x, _y, _z, _a, _b, _c,  feed ) { moveTo([_x,_y,_z,_a,_b,_c],                                                        {nameOfCallback:"onLinear5D", feedrate:feed });     }

function onLinear5D_DEPRECATED(_x, _y, _z, _a, _b, _c, feed) {
  var startPosition = (currentSection.getOptimizedTCPMode() == 0 ?   getCurrentPosition() : getMachineConfiguration().getPosition( getCurrentPosition(),   getCurrentDirection()   ) );
  var endPosition   = (currentSection.getOptimizedTCPMode() == 0 ? new Vector(_x, _y, _z) : getMachineConfiguration().getPosition( new Vector(_x, _y, _z), new Vector(_a, _b, _c)  ) );
  var distance = Vector.getDistance(startPosition, endPosition);
  var duration = distance/feed; //the duration of the move (in minutes)
  if(duration==0){duration = Math.pow(10,-8);};  //if the duration of the move is zero (which would happen if distance were zero, then set duration to a very small, finite, number, so that 1/duration will be finite.)
  
  if(debugging){
	  writeln("");
    // writeln("record " + getCurrentSectionId() + ":" + getCurrentRecordId());
    writeln("record " + getCurrentRecordId());
    writeln("onLinear5D("+_x+", "+_y+", "+_z+", "+_a+", "+_b+", "+_c+", "+feed+") was called)");
    reportPosition();
    writeln("startPosition: " + startPosition);
    writeln("endPosition: "   + endPosition);
    writeln("distance: "   + distance);
    writeln("duration: "   + duration*60.0 + " seconds");
    try {writeln("getFeedrate(): "   + getFeedrate());} catch(e){writeln("getFeedrate() threw exception.");}
	  }

  // getCurrentPosition() and getCurrentDirection() return the position and orientation of where we are coming from.
  // The line of gcode that we output here will move the machine from the point described by getCurrentPosition() to
  // the point described by _x, _y, _z, _a, _b, _c.
  
  
  //forcing the output of G93, G1, and inverse time feed rate may not be strictly necessary, but when it comes to using inverse time feedrate mode, I do not want to take any chances.
  feedOutput.format(1/duration);
  gMotionModal.reset(); //force to output motion mode (i.e. G1 or G0) on next call to gMotionModal.format();
  gFeedModeModal.reset(); //force to output the feedMode on next call to gFeedModeModal.format();
  feedOutput.reset(); //force to output the feed rate on next call to feedOutput.format();

  writeBlock(
    gFeedModeModal.format(93), 
    gMotionModal.format(1), 
    xOutput.format(_x), 
    yOutput.format(_y), 
    zOutput.format(_z), 
    aOutput.format(_a), 
    bOutput.format(_b), 
    cOutput.format(_c), 
    // feedOutput.format(1/duration),  //TODO: format the F word to achieve a specified relative precision (i.e. specify the number of signifricant figures, rather than the number of decimal places. The reason for this is that with inverse ti9me feed rate, we could conceivably ending up needing to specify some very small F values (for long duration moves).
    "F" + (new Decimal(1/duration)).toFixed()
  );
  feedOutput.reset(); //force to output the feed rate on next call to feedOutput.format();
}

function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
if(debugging){
	  writeln("");
	writeln("onCircular("+clockwise+", "+cx+", "+cy+", "+cz+", "+x+", "+y+", "+z+", "+feed+") was called)");
	  reportPosition();
	  }
  if (pendingRadiusCompensation >= 0) {
    error(localize("Radius compensation cannot be activated/deactivated for a circular move."));
    return;
  }

  var start = getCurrentPosition();

  if (isFullCircle()) {
    if (properties.useRadius || isHelical()) { // radius mode does not support full arcs
      linearize(tolerance);
      return;
    }
    switch (getCircularPlane()) {
    case PLANE_XY:
      writeBlock(gAbsIncModal.format(90), gPlaneModal.format(17), gMotionModal.format(clockwise ? 2 : 3), iOutput.format(cx - start.x, 0), jOutput.format(cy - start.y, 0), feedOutput.format(feed));
      break;
    case PLANE_ZX:
      writeBlock(gAbsIncModal.format(90), gPlaneModal.format(18), gMotionModal.format(clockwise ? 2 : 3), iOutput.format(cx - start.x, 0), kOutput.format(cz - start.z, 0), feedOutput.format(feed));
      break;
    case PLANE_YZ:
      writeBlock(gAbsIncModal.format(90), gPlaneModal.format(19), gMotionModal.format(clockwise ? 2 : 3), jOutput.format(cy - start.y, 0), kOutput.format(cz - start.z, 0), feedOutput.format(feed));
      break;
    default:
      linearize(tolerance);
    }
  } else if (!properties.useRadius) {
    switch (getCircularPlane()) {
    case PLANE_XY:
      writeBlock(gAbsIncModal.format(90), gPlaneModal.format(17), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), iOutput.format(cx - start.x, 0), jOutput.format(cy - start.y, 0), feedOutput.format(feed));
      break;
    case PLANE_ZX:
      writeBlock(gAbsIncModal.format(90), gPlaneModal.format(18), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), iOutput.format(cx - start.x, 0), kOutput.format(cz - start.z, 0), feedOutput.format(feed));
      break;
    case PLANE_YZ:
      writeBlock(gAbsIncModal.format(90), gPlaneModal.format(19), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), jOutput.format(cy - start.y, 0), kOutput.format(cz - start.z, 0), feedOutput.format(feed));
      break;
    default:
      linearize(tolerance);
    }
  } else { // use radius mode
    var r = getCircularRadius();
    if (toDeg(getCircularSweep()) > (180 + 1e-9)) {
      r = -r; // allow up to <360 deg arcs
    }
    switch (getCircularPlane()) {
    case PLANE_XY:
      writeBlock(gPlaneModal.format(17), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), "R" + rFormat.format(r), feedOutput.format(feed));
      break;
    case PLANE_ZX:
      writeBlock(gPlaneModal.format(18), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), "R" + rFormat.format(r), feedOutput.format(feed));
      break;
    case PLANE_YZ:
      writeBlock(gPlaneModal.format(19), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), "R" + rFormat.format(r), feedOutput.format(feed));
      break;
    default:
      linearize(tolerance);
    }
  }
}

//we have arranged things so that any function which results in movement of the machine must ultimately call 
// the moveTo function -- this is the only function which directly moves the machine (not counting movement that might happen as a result of tool changes and other 
// similar macros not directly orchestrated by the g-code.  
// I haven;t quite figured out what to do about canned cycles -- at the moment I am not treating canned cycles as movement, even though this is clearly wrong.
// putting all movement responsisbility in this one function lets us keep carefult track of the position of the machine,
// and re-use routines that are common to all motion.
// coordinatesOfDesitination: a six-member array of the form: [_x, _y, _z, _a, _b, _c]
//      any of the coordinates can be null, which is analagous to (and in some cases will output) a g-code line that omits some of the coordinates 
//      (null essentially stands for "the current coordinate value, whatever that may be")
// options:
//      boolean circularMovement 
//      map circularMovementArgs: a map consisting of the arguments {clockwise, cx, cy, cz} that the platform passed to the onCircular callback.
//      boolean rapid: controls whether we use G0 (i.e. rapid move) or feedrate-dependent movement commands.  Essentially, We use this to encode 
//      whether the onLinear or onRapid function is producing this movement.
//      string nameOfCallback: records which callback function, if any, invoked moveTo.
//      number feedrate
//      we will use G0 iff. the rapid option is present and is true.  it is an error to omit a feedrate option when the rapid option is false or absent.
//update : for simplicity, I have decided that I will use this single-purpose move function only for linear moves.  This means, at the moment,
// that circular moves and canned cycle moves will be handled entirely within other functions. (although, depending on settings, the onCircular function might
// call linearize() which would then result in the platform calling the variouos linear move functions repeatedly.
// therefore, the valid options will be 
// boolean rapid
// string nameOfCallback
// number feedrate

//update: by default a move is rapid.  It will be a non-rapid move iff. a feedrate is specified.
// therefore, the 'rapid' option is deprecated and will be ignored.


function moveTo(coordinatesOfDestination, options){
    if(typeof options == 'undefined'){options = {};}
    
    // log("before applying angularCoordinateOffset, coordinatesOfDestination: " + coordinatesOfDestination);
    //apply angularCoordinateOffset to any angular coordinates that are not undefined
    for(var i = 0;i<3;i++){
        if (coordinatesOfDestination[3+i] !== undefined){coordinatesOfDestination[3+i] += angularCoordinateOffset[i];}
    }
    // log("after applying angularCoordinateOffset, coordinatesOfDestination: " + coordinatesOfDestination);
    
    var coordinatesOfSource = getCurrentCoordinates();
    //fill in any undefined values of coordinatesOfDestination with the corersponding coordinate from coordinatesOfSource (which might also be undefined)
    coordinatesOfDestination = coordinatesOfSource.map(function(value, key){return (coordinatesOfDestination[key] == undefined ? value : coordinatesOfDestination[key]);});
    // log("after filling in undefined slots with known coordinates, coordinatesOfDestination: " + coordinatesOfDestination);

    //position and direction of the tool in the work frame:
    //this data describes, for each of the start and end of this move, almost the complete regid transform of the tool
    // (the only information that is missing is the rotational position of the tool spinning about its own axis).
    var startPosition;
    var endPosition;
    var startToolDirection;
    var endToolDirection;
    
    var distance;
    var duration;
    
    //deal with the case where there are some undefined (i.e. unknown) coordinates in the source and/or destination -- in that case, we won't be able to determine
    // the distance of the move, and therefore inverse time feedrate mode won't be useful.
    // we need to arrange things so that a preparatory move is done as part of the onSection() routine, so that by the time of the platform's 
    // first call to a motion handler, we confidently know
    // tyhe position of the machine (because we have issued a series of moveTo() calls that drove the machine to a specific, known position.
    if(coordinatesOfSource.concat(coordinatesOfDestination).some(function(x){return x == undefined;})){
        //if any element of coordinatesOfSource or coordinatesOfDestination is undefined...
        writeComment("The post processor has not yet driven the machine to a fully known state.");
        writeComment("as far as the post processor knows, we have...");
        writeComment("      coordinatesOfSource: " + coordinateListToString(coordinatesOfSource));
        writeComment(" coordinatesOfDestination: " + coordinateListToString(coordinatesOfDestination));
    } else {
        //if every element of coordinatesOfSource and coordinatesOfDestination is defined...
        // var startPosition = (currentSection.getOptimizedTCPMode() == 0 ?  getCurrentPosition() : getMachineConfiguration().getPosition( getCurrentPosition(),   getCurrentDirection()   ) );
            
        startPosition = getMachineConfiguration().getPosition(new Vector(coordinatesOfSource.slice(0,3)), new Vector(coordinatesOfSource.slice(3,6)));
        startToolDirection = getMachineConfiguration().getDirection(  new Vector(coordinatesOfSource.slice(3,6))   );
        
        // var endPosition   = 
            // (currentSection.getOptimizedTCPMode() == 0 ? 
                // new Vector(coordinatesOfDestination.slice(0,3)) 
                // : 
                // getMachineConfiguration().getPosition(
                    // new Vector(coordinatesOfDestination.slice(0,3)), 
                    // new Vector(coordinatesOfDestination.slice(3,6))
                // )  
            // );
        endPosition = getMachineConfiguration().getPosition(new Vector(coordinatesOfDestination.slice(0,3)), new Vector(coordinatesOfDestination.slice(3,6)));
        endToolDirection = getMachineConfiguration().getDirection(  new Vector(coordinatesOfDestination.slice(3,6))   );
        
        var distance = Vector.getDistance(startPosition, endPosition);
        var duration;
        if(options.feedrate){
            duration = distance/options.feedrate; //the duration of the move (in minutes)
            if(duration==0){duration = Math.pow(10,-8);};  //if the duration of the move is zero (which would happen if distance were zero, then set duration to a very small, finite, number, so that 1/duration will be finite.)
        } else {
            duration = undefined;
        }
        // at this point, we have the starting and ending position and toolDirections in the "work frame" (the frame that is bolted to the work piece.) -- these
        // are as specified by the unmodified hsmworks toolpath.
        // if the modifyToolOrientationInPostProcessing flag is on, then we want to compute a new endToolDirection, and then a corresponding new coordinatesOfDestination and then 
        // drive the machine to that destination (possibly in several incremental steps - in order to reduce the angular-vs.-linear toolpath deviation.).
    }
    


    logDebug("");
    logDebug("mapToWCS: " + mapToWCS);
    logDebug("mapWorkOrigin: " + mapWorkOrigin);
    logDebug("currentSection.getGlobalWorkOrigin(): " + currentSection.getGlobalWorkOrigin());
    logDebug("motion handler: " + options.nameOfCallback);
    logDebug("getMovementStringId(movement): " + getMovementStringId(movement));
    logDebug("     coordinatesOfSource: " + coordinateListToString(coordinatesOfSource));
    logDebug("coordinatesOfDestination: " + coordinateListToString(coordinatesOfDestination));
    logDebug("getCurrentRecordId(): " + getCurrentRecordId(),1);
    logDebug("getRotation():" + (getRotation().isIdentity() ? "(identity)" : getRotation()));
    logDebug("getTranslation():" + (getTranslation().isZero() ? "(zero)" :  getTranslation())); 
    logDebug("getCurrentGlobalPosition():" + getCurrentGlobalPosition()); 
    logDebug("getCurrentPosition():" + getCurrentPosition()); 
    logDebug("getMachineConfiguration().getPosition( getCurrentPosition(),   getCurrentDirection()   ):" + getMachineConfiguration().getPosition( getCurrentPosition(),   getCurrentDirection()   )); 
    try{logDebug("getMachineConfiguration().getPosition( new Vector(coordinatesOfSource.slice(0,3)), new Vector(coordinatesOfSource.slice(3,6))   ):" + getMachineConfiguration().getPosition(new Vector(coordinatesOfSource.slice(0,3)), new Vector(coordinatesOfSource.slice(3,6)))); } catch(e){}
    logDebug("getCurrentDirection():" + getCurrentDirection()); 
    logDebug("getMachineConfiguration().getDirection( getCurrentDirection()): " + getMachineConfiguration().getDirection( getCurrentDirection()));
    try{ logDebug("getMachineConfiguration().getDirection(  new Vector(coordinatesOfSource.slice(3,6))   ):" + getMachineConfiguration().getDirection(  new Vector(coordinatesOfSource.slice(3,6))   ));  } catch(e){}
    // logDebug("getWCSPosition(getCurrentPosition()): " + getWCSPosition(getCurrentPosition()));
    
    logDebug("feedrate: " + (options.feedrate ? lengthPerTimeFeedFormat.format(options.feedrate) : "(none - this is a rapid move)"));
    logDebug("duration: " + duration);
    logDebug("startPosition: " + startPosition);
    logDebug("endPosition: " + endPosition);
    logDebug("startToolDirection: " + startToolDirection);
    logDebug("endToolDirection: " + endToolDirection);
    // try{logDebug("getMachiningDistance(): " + getMachiningDistance(tool.getNumber()))} catch(e) {logDebug("getMachiningDistance() threw an exception: " + e);};
    
    // logDebug("");
    // mapToWcs=true; mapWorkOrigin=true;
    // logDebug("mapToWCS: " + mapToWCS);
    // logDebug("mapWorkOrigin: " + mapWorkOrigin);
    // logDebug("getCurrentGlobalPosition():" + getCurrentGlobalPosition()); 
    // logDebug("getCurrentPosition():" + getCurrentPosition()); 
    
    // logDebug("");
    // mapToWcs=false; mapWorkOrigin=true;
    // logDebug("mapToWCS: " + mapToWCS);
    // logDebug("mapWorkOrigin: " + mapWorkOrigin);
    // logDebug("getCurrentGlobalPosition():" + getCurrentGlobalPosition()); 
    // logDebug("getCurrentPosition():" + getCurrentPosition()); 
    
    // logDebug("");
    // mapToWcs=true; mapWorkOrigin=false;
    // logDebug("mapToWCS: " + mapToWCS);
    // logDebug("mapWorkOrigin: " + mapWorkOrigin);
    // logDebug("getCurrentGlobalPosition():" + getCurrentGlobalPosition()); 
    // logDebug("getCurrentPosition():" + getCurrentPosition()); 
    
    // logDebug("");
    // mapToWcs=false; mapWorkOrigin=false;
    // logDebug("mapToWCS: " + mapToWCS);
    // logDebug("mapWorkOrigin: " + mapWorkOrigin);
    // logDebug("getCurrentGlobalPosition():" + getCurrentGlobalPosition()); 
    // logDebug("getCurrentPosition():" + getCurrentPosition()); 
    
    // mapToWcs=true; mapWorkOrigin=true;
    // // changing mapToWcs and mapWorkOrigin here has no effect -- it looks they apply only at the time the platform is preparing the points for the post processor.
    
    // logDebug("getCurrentNCLocation(): " + getCurrentNCLocation());
    // try{logDebug("getEnd(): " + getEnd());}catch(e){}
    try{logDebug("getLength() : " + getLength());}catch(e){}
    logDebug(    "distance    : " + distance);
    
    
    
    // logDebug(getPositionReport(),1);

    if(properties.feedrateMode == "movesPerTime" && options.feedrate!==undefined){
        //when G93 (inverse time feedrate mode) is active, an F word must appear on every line 
        //which has a G1, G2, or G3 motion and an F word on a line that does not have G1, G2, or G3 is ignored (according to http://linuxcnc.org/docs/html/gcode/g-code.html#gcode:g93-g94-g95)
        //therefore, if we are to use inverse time feedrate mode, every non-rapid motion line muust have a motion command (G1 G2 or G3) and an F word.
        gMotionModal.reset(); 
        feedOutput.reset(); 
     // gFeedModeModal.reset(); 
    }


    var x = (coordinatesOfDestination[0] ===undefined ? "" :     xOutput.format( coordinatesOfDestination[0]) );
    var y = (coordinatesOfDestination[1] ===undefined ? "" :     yOutput.format( coordinatesOfDestination[1]) );
    var z = (coordinatesOfDestination[2] ===undefined ? "" :     zOutput.format( coordinatesOfDestination[2]) );
    var a = (coordinatesOfDestination[3] ===undefined ? "" :     aOutput.format( coordinatesOfDestination[3]) );
    var b = (coordinatesOfDestination[4] ===undefined ? "" :     bOutput.format( coordinatesOfDestination[4]) );
    var c = (coordinatesOfDestination[5] ===undefined ? "" :     cOutput.format( coordinatesOfDestination[5]) );
    var f = (options.feedrate            ===undefined ? "" :  (properties.feedrateMode == "movesPerTime" ? (duration === undefined ? "" : feedOutput.format(1.0/duration)) : feedOutput.format(options.feedrate)));
    
    if(x || y || z || a || b || c || f){
        // compute radiusCompensationWords, a (possibly empty) array of strings that are to be inserted in the gcode line.
        var radiusCompensationWords = [];
        //handle all of the possible situations under which radius compensation is not allowed,
        if(pendingRadiusCompensation < 0){
            //this is not an error as such, but it means that we will not attempt to set radius compensation
        } else if(options.rapid){
             error(localize("Radius compensation mode cannot be changed at rapid traversal."));
             return;
        } else if (getCircularPlane() != PLANE_XY){
            error("The circular plane must be PLANE_XY in order to enable (or disable, I think) cutter radius compensation.");
            return;
        } else if (!(x || y || z || a || b || c)){
            //this is not an error as such, but it means that we will not attempt to set radius compensation
        } else if (options.nameOfCallback == "onLinear5D"){
            error(localize("Radius compensation cannot be activated/deactivated for 5-axis move."));
            return;
        } else if (options.nameOfCallback == "onCircular") {
            error(localize("Radius compensation cannot be activated/deactivated for a circular move."));
            return;
        } else {
            //in this case, radius compensation is allowed and we want to do it
            switch (pendingRadiusCompensation) {
            case RADIUS_COMPENSATION_LEFT:
                pOutput.reset();
                radiusCompensationWords = [pOutput.format(tool.diameter), gFormat.format(41)];
                // writeBlock(gMotionModal.format(1), pOutput.format(tool.diameter), gFormat.format(41), x, y, z, f);
                break;
            case RADIUS_COMPENSATION_RIGHT:
                pOutput.reset();
                radiusCompensationWords = [pOutput.format(tool.diameter), gFormat.format(42)];
                // writeBlock(gMotionModal.format(1), pOutput.format(tool.diameter), gFormat.format(42), x, y, z, f);
                break;
            default:
                radiusCompensationWords = [gFormat.format(40)];
                // writeBlock(gMotionModal.format(1), gFormat.format(40), x, y, z, f);
            }
            pendingRadiusCompensation = -1;
        }
        // I don't understand the business with the pendingRadiuscompensation variable.  Why not simply spit out a statement like "G41 P0.342" on its own 
        // line immediately when 
        // onRadiusCompensation is called?  Does the g-code interpreter require G40, G41, and G42 words always to appear on the same line with a G1 or G0 word?
        // --> based on the linuxcnc g-code documentation (http://linuxcnc.org/docs/html/gcode/g-code.html#gcode:g40), it seems
        // that it is an error to change radius compensation right before a non-linear move (which probably means a circle or a canned cycle, but might also 
        // include motion that
        // has a rotatry component).
        // I suspect that the HSMWorks platform is careful, but not fully trustworthy, about only turning on radius compensation mode before a linear move, and that 
        // from the information available to javascript inside the onRadiusCompensation function body, it is not possible to tell if the next move is a move
        // of the type before which it is allowable to change radius compensation.  However, this information is available in the motion handlers (onLinear, onRapid... etc.) 
        // Therefore, the pendingRadiusCompensation variable is used as a cache to allow us to wait until we have the information needed to detect possible errors before 
        // attempting to emit the g-code to change radius compensation.  That's my theory, anyway.
        if(
            !(x || y || z || a || b || c) // i.e. the only word whose value needs to be set is the F word // I am not totally convinced that this scheme is valid for full-circle circular moves, because in that case, we might have a non-changing x,y,z,a,b,c words but nevertheless might need to specify a new feedrate (and run the circle command)
            &&  getNextRecord().isMotion()
        ) {
            // in this case, only the F-word needs to be emitted, but the next record is a motion, so we might as
            // well wait until we are processing the next record and emit the new feedrate then along with the 
            // motion command words.
            feedOutput.reset(); // force feed on next line
        } else {
            var motionCommandWord;
            gMotionModal.reset();
            if(options.feedrate){
                motionCommandWord = gMotionModal.format(1);
            } else {
                motionCommandWord = gMotionModal.format(0);
                feedOutput.reset();
            }
            // var arguments  = [motionCommandWord].concat(radiusCompensationWords).concat([x, y, z, a, b, c, f]);
            // logDebug("arguments to writeBlock: " + arguments);
            // this.writeBlock.apply( [motionCommandWord].concat(radiusCompensationWords).concat([x, y, z, a, b, c, f]));
            // // the above caused the string "[object Arguments]" to be written into the gcode file -- probably something weird related to the apply method.
            //fortunately, it seems that writeBlock accepts an array of strings as an argument and does what we want it to do:
            if(properties.feedrateMode == "movesPerTime"){}; 
            this.writeBlock( 
                (options.feedrate === undefined ? [] : gFeedModeModal.format( properties.feedrateMode == "movesPerTime" ? 93 : 94 )),
                motionCommandWord, 
                gAbsIncModal.format(90),
                radiusCompensationWords, 
                (x?x:" ".repeat(xyzFormat.format(0).length)), 
                (y?y:" ".repeat(xyzFormat.format(0).length)), 
                (z?z:" ".repeat(xyzFormat.format(0).length)), 
                (a?a:" ".repeat(abcFormat.format(0).length)), 
                (b?b:" ".repeat(abcFormat.format(0).length)), 
                (c?c:" ".repeat(abcFormat.format(0).length)), 
                (f?f:" ".repeat(feedFormat.format(0).length))
            );
            lastCoordinates = coordinatesOfDestination;
        }  
    } 
}

//returns an array of numbers of the form [x,y,z,a,b,c] representing the current
//coordinates of the controlled point.  These are (and should be) the numbers
//that are displayed in the six position dro's of mach3 when not in "machine
//coordinates" mode and the numbers  that HSMworks passes as arguments to the
//motion handlers.


function getCurrentCoordinates(){
    return lastCoordinates;
    // I don't think getDurrentDirection() returns a list of the three angular coordinates of the current machine state.  rather, it refers to the direction that the bit is pointing in (in some frame or another).
    // What is the function to get the current angular coordinates of the machine state.
}

// we will call the forgetCurrentDoordinates function whenever we issue a
// command that would cause the current offset to change (for instance one of
// the work offset setting commands - G54, G55, etc., or the tool length offset
// command, or a G53 or G28 (movement relative to the machine's constant frame)
// or a command like a toolchange or probe operation that would cause Mach3 to
// drive the the machine to some state that we have no knowledge of here in the
// post processor.  I suppose that all of the aforementioned actions could be
// described as actions where the current coordinates of the controlled point
// change to values that are depenedent on registers in Mach3 (like the work
// offset registers) that are subject to change as the machine is used, and
// whose values we have no knowledge of here in the post-processor. this
// function will, by default, forget (i.e. set the corresponding array entry 
// in lastCoordinates to undefined) all coordinates. however, if this
// function is given arguments, then the arguments are expected to be (After
// flattening) the indices (one of (0,1,2,3,4,5)) of lastCoordinates to be set
// to undefined. and only the specified coordinates will be set to undefined.
 

function forgetCurrentCoordinates(){
    arguments = flatten(arguments);
    (arguments.length == 0 ? [0,1,2,3,4,5] : arguments).map(
        function(index){
            lastCoordinates[index]=undefined;
            [xOutput,yOutput,zOutput,aOutput,bOutput,cOutput][index].reset();  //this act is not strictly part of the essence of the forgetCoordinates() function, but it doesn't hurt and it is convenient to have it here.
        }
   );
}

//takes in a list of numbers of the form [x,y,z,a,b,c]
//spits out a string like "X3.456 Y28.567 Z-48.9898 A578.2 ..."
function coordinateListToString(coordinateList){
    var prefixes = ["X","Y","Z","A","B","C"];
    return coordinateList.map(
        function(value,key){
            var formatter = (key < 3 ? xyzFormat : abcFormat);
            return prefixes[key] + (
                (
                    (value == undefined) 
                    ?
                    repeatStringNumTimes("-",formatter.format(0).length)  //a string filled entirely with "-", the same length as the number string would be (this scheme produces visually appealing results only when the formatter happens to produce strings of uniform width.
                    :
                    formatter.format(value)
                )
            );
        }
    ).join(" ");
}

function onCommand(command) {
  switch (command) {
  case COMMAND_START_SPINDLE:
    onCommand(tool.clockwise ? COMMAND_SPINDLE_CLOCKWISE : COMMAND_SPINDLE_COUNTERCLOCKWISE);
    return;
  case COMMAND_LOCK_MULTI_AXIS:
    return;
  case COMMAND_UNLOCK_MULTI_AXIS:
    return;
  case COMMAND_BREAK_CONTROL:
    return;
  case COMMAND_TOOL_MEASURE:
    return;
  }
  var stringId = getCommandStringId(command);
  var mcode = {
      COMMAND_STOP                       :  0,
      COMMAND_OPTIONAL_STOP              :  1,
      COMMAND_END                        :  2,
      COMMAND_SPINDLE_CLOCKWISE          :  3,
      COMMAND_SPINDLE_COUNTERCLOCKWISE   :  4,
      COMMAND_STOP_SPINDLE               :  5,
      COMMAND_ORIENTATE_SPINDLE          : 19,
      COMMAND_LOAD_TOOL                  :  6,
      COMMAND_COOLANT_ON                 :  8, // flood
      COMMAND_COOLANT_OFF                :  9
    }[stringId];
  if (mcode != undefined) {
    writeBlock(mFormat.format(mcode),{trailingComment:  stringId });
  } else {
    onUnsupportedCommand(command);
  }
}

function onParameter(name,value){
	parameterNames.push(name);
    // if(typeof currentSection == "undefined"){
        // globalParameters[name] = value;
    // } else {
        // if(sectionParametersBySection[currentSection.getId()] === undefined){sectionParametersBySection[currentSection.getId()] = {};}
        // sectionParametersBySection[currentSection.getId()][name] = value;
    // }
    
    // logDebug(">>>>>>>>>>>>>>>>>  onParameter(" + name + ","+ value +") ");
	if(name=="action")
	{
		onAction(value);
	} else {
		//do nothing
		//writeComment("onParameter -- " + name + ", " + value + " -- ");
		return;
	}
}

function onSectionEnd() {
  writeBlock(gPlaneModal.format(17));

  if (((getCurrentSectionId() + 1) >= getNumberOfSections()) ||
      (tool.number != getNextSection().getTool().number)) {
    onCommand(COMMAND_BREAK_CONTROL);
  }

  //anti-windup provision (i.e. set the G92 offset so that the current a-coordinate becomes a number in the range [0, 360] without changing value mod 360.
  
  
  forceAny();
  
  writeln(doNothingCloser);
}

function onClose() {
  writeln("");

  onCommand(COMMAND_COOLANT_OFF);
 
  writeRetract(Z);

   
  //setWorkPlane(new Vector(0, 0, 0)); // reset working plane
  //the above setWorkPlane() serves no useful purpose, as far as I can tell, so I have commented it out.  
  //the above setWorkPlane was causing a "G90 G0 A0" to be issued at the end of the program,
  // which, when combined my gcode transformer, caused some unneccessary motion.
    
  if (!machineConfiguration.hasHomePositionX() && !machineConfiguration.hasHomePositionY()) {
    if (properties.useG28) {
      writeBlock(gFormat.format(28), gAbsIncModal.format(91), "X" + xyzFormat.format(0), "Y" + xyzFormat.format(0)); // return to home
	}
  } else {
    var homeX;
    if (machineConfiguration.hasHomePositionX()) {
      homeX = "X" + xyzFormat.format(machineConfiguration.getHomePositionX());
    }
    var homeY;
    if (machineConfiguration.hasHomePositionY()) {
      homeY = "Y" + xyzFormat.format(machineConfiguration.getHomePositionY());
    }
	
    //writeBlock(gAbsIncModal.format(90), gFormat.format(53), gMotionModal.format(0), homeX, homeY); 
	writeBlock(gAbsIncModal.format(90)); //2015-10-30 : commented out above line and replaced with this one because homeX and homeY in my particular configuration are arbitrary and I don't want to send the machine to some arbitrary position.
  }

  onImpliedCommand(COMMAND_END);
  onImpliedCommand(COMMAND_STOP_SPINDLE);
  writeBlock(mFormat.format(30), "(PROGRAM END and rewind)"); // stop program, spindle stop, coolant off
}

function onPassThrough(value){
	writeln(value);
}


function onTerminate(){ 
   if(properties.commandToRunOnTerminate && typeof(properties.commandToRunOnTerminate) == "string" && properties.commandToRunOnTerminate.length > 0){
        var re = new RegExp("\\$\\{([^\\}]+)\\}","g");
        // properties.commandToRunOnTerminate can contain subsrings of the form ${something goes here}.  The stuff between the curly braces will be evaluated as javascript expression, the value of which will be cast to a String and inserted in polace of the ${...} expression.
        //to-do: provide a scheme to escape a right curly brace.
        // it looks like hsmworks is already doing something special with the ${...} syntax.  when I include an arbitrary string inside the curly braces, hsmworks 
        // replaces any instances of ${...} in the string entered in the ui with the stuff between the curly braces.
        // fortunately, we can achieve the desired effect by using two dollar signs instead of one -- this seems to prevent hsmworks from giving special treatment (except for stripping one dollar sign).
        var resolvedCommand = properties.commandToRunOnTerminate.replace(re, function(match, p1){return String(eval(p1));});
        // resolvedCommand = ("${getOutputPath()}").replace(re, function(match, p1){return String(eval(p1));});
        try{
            execute(
                "cmd", //path
                "/c " + resolvedCommand, //arguments
                false, //hide
                FileSystem.getFolderPath(getOutputPath()) //working folder -- same as the folder in which the gcode is being deposited.
            );
        } catch (e) {
            
        }
    }
    
    //a temporary hack to work-around hsmworks's behavior of momentarily deleting the gcode file before re-creating it, which screws up my automatic monitoring of the file contents in notepad++.
    try{
        // execute(
            // "cmd", //path
            // "/c " + "copy /y \"" + FileSystem.getFilename(getOutputPath()) + "\" \"" + FileSystem.getFilename(getOutputPath()) + "\"" , //arguments
            // false, //hide
            // FileSystem.getFolderPath(getOutputPath()) //working folder -- same as the folder in which the gcode is being deposited.
        // );
        FileSystem.copyFile(
            //source: 
            getOutputPath(), 
            
            //destination
            FileSystem.getCombinedPath(
                FileSystem.getFolderPath(getOutputPath()), 
                "2" + FileSystem.getFilename(getOutputPath())
           )
       );
    } catch (e) {
        
    }
    
}
//}


/** Force output of X, Y, and Z. */
function forceXYZ() {
  xOutput.reset();
  yOutput.reset();
  zOutput.reset();
}

/** Force output of A, B, and C. */
function forceABC() {
  aOutput.reset();
  bOutput.reset();
  cOutput.reset();
}

/** Force output of X, Y, Z, A, B, C, and F on next output. */
function forceAny() {
  forceXYZ();
  forceABC();
  feedOutput.reset();
}

var currentWorkPlaneABC = undefined;

function forceWorkPlane() {
  currentWorkPlaneABC = undefined;
}

function setWorkPlane(abc) {
  writeComment("commencing setWorkPlane()");
    logDebug("setWorkPlane("+abc+") was called.");
  if (!machineConfiguration.isMultiAxisConfiguration()) {
    writeComment("setWorkPlane() is finished. machineConfiguration.isMultiAxisConfiguration() is false, so we did not need to do anything.");
  } else{
      if (!(
            (currentWorkPlaneABC == undefined) ||
            abcFormat.areDifferent(anglesModOneRevolution(abc).x, anglesModOneRevolution(currentWorkPlaneABC).x) ||
            abcFormat.areDifferent(anglesModOneRevolution(abc).y, anglesModOneRevolution(currentWorkPlaneABC).y) ||
            abcFormat.areDifferent(anglesModOneRevolution(abc).z, anglesModOneRevolution(currentWorkPlaneABC).z)
        )
      ) { 
        // if currentWorkPlaneABC is defined AND the argument, abc, is the same as currentWorkPlaneABC (mod 360 degrees), then we do not need to do anything
        writeComment("setWorkPlane() is finished. We did not need to do anything.");
      } else {
          moveTo(
            [
                undefined, //x
                undefined, //y
                undefined //z
            ].concat(
                vectorToArray(
                    machineConfiguration.remapToABC(abc, getCurrentDirection())
                )
            )
          );
          currentWorkPlaneABC = abc;
      }
  }
  writeComment("setWorkPlane() is finished.");
}

//I suspect that the following two variables really ought to be private static variables within the getWorkPlaneMachineABC() function.
var closestABC = true; // choose closest machine angles
var currentMachineABC;

function getWorkPlaneMachineABC(workPlane) {
  var W = workPlane; // map to global frame

  var abc = machineConfiguration.getABC(W);
  if (closestABC) {
    if (currentMachineABC) {
      abc = machineConfiguration.remapToABC(abc, currentMachineABC);
    } else {
      abc = machineConfiguration.getPreferredABC(abc);
    }
  } else {
    abc = machineConfiguration.getPreferredABC(abc);
  }
  
  try {
    abc = machineConfiguration.remapABC(abc);
    currentMachineABC = abc;
  } catch (e) {
    error(
      localize("Machine angles not supported") + ":"
      + (machineConfiguration.isMachineCoordinate(0) ? "A" + abcFormat.format(abc.x) : "")
      + (machineConfiguration.isMachineCoordinate(1) ? "B" + abcFormat.format(abc.y) : "")
      + (machineConfiguration.isMachineCoordinate(2) ? "C" + abcFormat.format(abc.z) : "")
    );
  }
  
  var direction = machineConfiguration.getDirection(abc);
  if (!isSameDirection(direction, W.forward)) {
    error(localize("Orientation not supported."));
  }
  
  if (!machineConfiguration.isABCSupported(abc)) {
    error(
      localize("Work plane is not supported") + ":"
      + conditional(machineConfiguration.isMachineCoordinate(0), " A" + abcFormat.format(abc.x))
      + conditional(machineConfiguration.isMachineCoordinate(1), " B" + abcFormat.format(abc.y))
      + conditional(machineConfiguration.isMachineCoordinate(2), " C" + abcFormat.format(abc.z))
    );
  }

  //var tcp = true;
  var tcp = false; //trying this per forum post. -Neil
  if (tcp) {
    setRotation(W); // TCP mode
  } else {
    var O = machineConfiguration.getOrientation(abc);
    
    log(
        "\n" + 
        "we will call machineConfiguration.getRemainingOrientation(" + "\n" +
        "\t" + abc + ", " + "\n" + 
        "\t" + W + "\n" + 
        ")" + "\n"
    );

    log("u axis direction: " + machineConfiguration.getAxisU().getAxis());
    
    
    var R = machineConfiguration.getRemainingOrientation(abc, W);
    var theta = abc.x;
    log("theta is " + (theta*180.0/Math.PI) + " degrees");
    log("R is " + R);
    
    // log("initially, R is " + R);
    // log("initially, W is " + W);
    // // log("R.multiply(W): "  + R.multiply(W));
    // // log("(new Matrix(new Vector(1,0,0), theta)): "  + (new Matrix(new Vector(1,0,0), theta)));
    // // var error = R.multiply(W).subtract(new Matrix(new Vector(1,0,0), theta));
    // var error = Matrix.diff(R.multiply(W), new Matrix(new Vector(1,0,0), theta));
    // // log("typeof error: " + typeof error)
    // // log("typeof R.multiply(5): " + typeof R.multiply(5))
    // // log("typeof R: " + typeof R)
    // log("error: " + error);
    // log("matrixTolerantEquals(R.multiply(W), new Matrix(new Vector(1,0,0), theta)): " + matrixTolerantEquals(R.multiply(W), new Matrix(new Vector(1,0,0), theta)));
    // log("max element in error: " + Math.max(flatten(matrixToArray(error)).map(Math.abs)));
    // log("after computing, R is " + R);
    // log("after computing, W is " + W);
    // log(dumpObjectToString(Matrix));
    
    
    setRotation(R);
  }
  
  return abc;
}

//returns a nested array of the matrice's elements
function matrixToArray(m){
    a = [[],[],[]];
    for( rowIndex=0; rowIndex<3; rowIndex++){
        for( columnIndex=0; columnIndex<3; columnIndex++){
            a[rowIndex][columnIndex] = m.getElement(rowIndex, columnIndex);
        }
    }
    return a;    
}

function arrayToMatrix(a){
    m= new Matrix();
    for( rowIndex=0; rowIndex<3; rowIndex++){
        for( columnIndex=0; columnIndex<3; columnIndex++){
            m.setElement(rowIndex, columnIndex, a[rowIndex][columnIndex]);
        }
    }
    return m;
}

function getInverseOfMatrix(m){
    
}

function matrixTolerantEquals(a,b,tolerance){
    if(typeof tolerance == "undefined"){tolerance = Math.pow(10,-8);}
    //we will consider the matrices a and b to be equal to one another (within the tolerance)
    // iff. the maximum of the absolute values of the elements of the difference of a and b is less 
    // than the 
    // absolute value of the tolerance.
    return getMaxOfArray(flatten(matrixToArray(Matrix.diff(a,b))).map(Math.abs)) <= Math.abs(tolerance);
}

function getMaxOfArray(numArray) {
  return numArray.reduce(function(a, b) {
        return Math.max(a, b);
    });
}

function setWorkOffset(workOffsetNumber){
    //we will treat workOffsetNumber=0 as equivalent to workOFfsetNumber=1
    if (workOffsetNumber == 0) {
        warning(localize("Work offset has not been specified. Using G54 as WCS."));
        setWorkOffset(1);
    }
    
    //we will use the static variable lastWorkOffsetNumber to keep track of the last work offset that we set when this function was last called.
    // this will help us decide when the work offset has changed, so that we can call forgetCurrentCoordinates().
    if(setWorkOffset.lastWorkOffsetNumber==undefined || setWorkOffset.lastWorkOffsetNumber!=workOffsetNumber){forgetCurrentCoordinates();}
    if (workOffsetNumber > 254 || workOffsetNumber < 0){
        error(localize("Work offset out of range."));
    } else if (workOffsetNumber > 0){      
        writeBlock(
            (workOffsetNumber > 6  ? [gFormat.format(59), "P" + workOffsetNumber] : gFormat.format(53 + workOffsetNumber)),
            {'trailingComment': "using work offset number " + workOffsetNumber}
        );
        //note: G59 P1 is equivalent to G54, G59 P2 is equivalent to G55, and so forth.
    }
    setWorkOffset.lastWorkOffsetNumber=workOffsetNumber;
}

function setToolLengthOffset(toolLengthOffsetNumber){
    if (toolLengthOffsetNumber > 256) {
        error(localize("The tool length offset (" + toolLengthOffsetNumber + ") is out of range."));
        return;
    } 
    writeBlock(gFormat.format(43), hFormat.format(toolLengthOffsetNumber), {trailingComment: "enable tool length offset"});
    forgetCurrentCoordinates();
}

function cancelToolHeightOffset(){
    writeBlock(gFormat.format(49), {trailingComment: "cancel tool-length offset"});
    forgetCurrentCoordinates();
}


function setUnit(unit){   
  switch (unit) {
     case IN:
       writeBlock(gUnitModal.format(20), {trailingComment: "unit mode: inches"});
       break;
     case MM:
       writeBlock(gUnitModal.format(21), {trailingComment: "unit mode: millimeters"});
       break;
  }
  forgetCurrentCoordinates();
}

function getCommonCycle(x, y, z, r) {
  forceXYZ();
  return [xOutput.format(x), yOutput.format(y),
    zOutput.format(z),
    "R" + xyzFormat.format(r)];
}

var pendingRadiusCompensation = -1;

/*
returns the norm of a vector (because the Vector::getLength() function does not seem to be present.)
*/
function norm(x) {
  // return Math.hypot( x.getX(), x.getY(), x.getZ() );
  return Math.sqrt(
       Math.pow(x.getX(),2) 
     + Math.pow(x.getY(),2) 
     + Math.pow(x.getZ(),2) 
  );
}

// function anglesToRevolutionRemainder(x) {
    // //x is expected be a Vector
    // return new Vector(
       // (x.getX() % (2*Math.PI))/(2*Math.PI),
       // (x.getY() % (2*Math.PI))/(2*Math.PI),
       // (x.getZ() % (2*Math.PI))/(2*Math.PI)
    // );
// }

//takes a triple of angles (an object of type vector)
//returns a new triple of angles,m each equal to the correspponding input angle mod 1 revolution
function anglesModOneRevolution(x){
    return new Vector(
       mod(x.getX(), 2*Math.PI),
       mod(x.getY(), 2*Math.PI),
       mod(x.getZ(), 2*Math.PI)
    );
    // var returnValue = machineConfiguration.remapToABC(x, new Vector(0,0,0));
    writeln("anglesModOneRevolution is returning " + returnValue);
    return returnValue;
}


// //diagnostic function to figure out what the hell HSMWorks is doing
// function getPositionReport(){
  // var message = "";
  // if(!getRotation().isIdentity()){
     // message += "getRotation():" + (getRotation().isIdentity() ? "(identity)" : getRotation()) + "\n";
  // }

  // if(!getTranslation().isZero()){
    // message += "getTranslation():" + (getTranslation().isZero() ? "(zero)" :  getTranslation()) + "\n";
  // }
  
  // message += "getCurrentPosition(): " + getCurrentPosition() + "\n";
  // //message += "getCurrentGlobalPosition(): " + getCurrentGlobalPosition() + "\n";
  // message += "getCurrentDirection(): " + getCurrentDirection() + "\n";
  // // message += "anglesToRevolutionRemainder(getCurrentDirection()): " + anglesToRevolutionRemainder(getCurrentDirection()) + "\n";
  // // message += "getPositionU(0): " + getPositionU(0) + "\n";
  // // message += "getPositionU(0.9999): " + getPositionU(0.9999) + "\n";
  // // message += "getPositionU(1): " + getPositionU(1) + "\n";
  // // try {message += "getFramePosition(getCurrentPosition()): " + getFramePosition(getCurrentPosition()) + "\n";} catch(e){}
  // // try {message += "getFrameDirection(getCurrentDirection()): " + getFrameDirection(getCurrentDirection())  + "\n";} catch(e){}

  // // try {message += "start: " + start + "\n";} catch(e){message += "start threw exception" + "\n";}
  // // try {message += "end: " + end + "\n";} catch(e){message += "end threw exception" + "\n";}
  
  // // message += "getMachineConfiguration().getDirection(new Vector(0,0,0)): " + getMachineConfiguration().getDirection(new Vector(0,0,0)) + "\n";
  // // message += "getMachineConfiguration().getDirection(new Vector(90,0,0)): " + getMachineConfiguration().getDirection(new Vector(90,0,0)) + "\n";
  // // message += "getMachineConfiguration().getDirection(new Vector(Math.PI/2,0,0)): " + getMachineConfiguration().getDirection(new Vector(Math.PI/2,0,0)) + "\n";
  // // getMachineConfiguration().getDirection() expects an argument in units of radians, which is as it should be.

  // // var direction = 
  // //    Vector(
  // //        getMachineConfiguration().getDirection(getCurrentDirection()).getX(),
  // //        getMachineConfiguration().getDirection(getCurrentDirection()).getY(),
  // //        getMachineConfiguration().getDirection(getCurrentDirection()).getZ()
  // //    );
  
  // // dump(direction, "direction");
  // // message += "typeof(getMachineConfiguration().getDirection(getCurrentDirection())): " + typeof(getMachineConfiguration().getDirection(getCurrentDirection())) + "\n";
  // // dump(getMachineConfiguration().getDirection(getCurrentDirection()), "getMachineConfiguration().getDirection(getCurrentDirection())");
  // // message += "getCurrentNCLocation(): " + getCurrentNCLocation() + "\n";
  
  // return message;
// }

/*
Inserts an external file into the gcode output.  the path is relative to the output gcode file (or can also be absolute).
If the file estension is "php", this is a special case: in this case, the php file is executed and the stdout is included in 
the output gcode file.
*/
function includeFile(path){
	writeln("(>>>>>>>>>>>>>>>>>  file to be included: " + path + ")"); //temporary behavior for debugging.

	//if path is not absolute, it will be assumed to be relative to the folder where the output file is being placed.
	
	var absolutePath = 
		FileSystem.getCombinedPath(
			FileSystem.getFolderPath(getOutputPath()) ,
			path
		);
    
    writeln("(>>>>>>>>>>>>>>>>>  absolute path of file to be included: " + absolutePath + ")"); //temporary behavior for debugging.
	
	var fileExtension = FileSystem.getFilename(path).replace(FileSystem.replaceExtension(FileSystem.getFilename(path)," ").slice(0,-1),""); //this is a bit of a hack to work around the fact that there is no getExtension() function.  Strangely, FileSystem.replaceExtension strips the period when, and only when, the new extension is the emppty string.  I ought to do all of this with RegEx.  //bizarrely, replaceExtension() evidently regards the extension of the file whose name is "foo" to be "foo" --STUPID (but this weirdness won't affect my current project.)
	
	// //writeln("getOutputPath():\""+getOutputPath()+"\"");
	// //writeln("FileSystem.getFilename(path):\"" + FileSystem.getFilename(path) + "\"");
	// writeln("fileExtension:\""+fileExtension+"\"");
	// writeln("absolutePath:\"" + absolutePath + "\"");
	// writeln("FileSystem.getTemporaryFolder():\"" + FileSystem.getTemporaryFolder() + "\"");
	var pathOfFileToBeIncludedVerbatim;
	var returnCode;
	switch(fileExtension.toLowerCase()){ //FIX
		case "php" :
			//FileSystem.getTemporaryFile() was not working, until I discovered that the stupid thing was trying to create a file in a non-existent temporary folder.
			// Therefore, I must first ensure that the temporary folder exists.  STUPID!
			if(! FileSystem.isFolder(FileSystem.getTemporaryFolder())){FileSystem.makeFolder(FileSystem.getTemporaryFolder());}
			var pathOfTempBufferFile = FileSystem.getTemporaryFile("");
			var pathOfCamParametersFile = FileSystem.getTemporaryFile("");
			//writeln("pathOfTempBufferFile:\""+pathOfTempBufferFile+"\"");
			// returnCode = execute("cmd", "/c php \""+absolutePath+"\" > \""+pathOfTempBufferFile+"\"", false, ""); //run it through php and collect the output
            //had to hard-code the path to php executable due to system path not taking effect unless I were to restart solidworks:
            //The "2>&1" redirects stderr to stdout, so that if an error occurs with the running of the php file, at least some 
            // indication of the error makes its way into the gcode file where the user has a hope of noticing it.
            // might alos make sense to raise an exception if the returnCode is not zero and log the error in the hsmworks post processor log.
            var pathOfParametersDumpFile = FileSystem.getCombinedPath(FileSystem.getFolderPath(getOutputPath()),"parameters.json"); 
            
            //dump the section parameters to a file, which the php script can read
            camParametersFile = new TextFile(pathOfCamParametersFile,true,"ansi");
            
            camParametersFile.write(
                JSON.stringify(
                    {
                        'sectionParameters': getSectionParameters(currentSection),
                        'globalParameters': getGlobalParameters(),
                        'postProcessor':this
                    }
                )
            );
            camParametersFile.close();
			returnCode = execute("cmd", "/c c:/php/php.exe \""+absolutePath+"\" --parameterFile=\"" + pathOfParametersDumpFile + "\" --camParametersFile=\"" + pathOfCamParametersFile + "\" > \""+pathOfTempBufferFile+"\" 2>&1", false, ""); //run it through php and collect the output
			//writeln("returnCode:"+returnCode);
            writeln("(>>>>>>>>>>>>>>>>>  temp buffer file: " + pathOfTempBufferFile + ")"); //temporary behavior for debugging.
			pathOfFileToBeIncludedVerbatim = pathOfTempBufferFile;
			break;
		
		default :
			pathOfFileToBeIncludedVerbatim = absolutePath;
			break;
	
	}
	
    log("pathOfFileToBeIncludedVerbatim: " + pathOfFileToBeIncludedVerbatim);
	var myTextFile = new TextFile(pathOfFileToBeIncludedVerbatim,false,"ansi");
	var lineCounter = 0;
	var line;
	while(!function(){try {line=myTextFile.readln(); eof = false;} catch(error) {eof=true;} return eof;}())  //if the final line is empty (i.e. if the last character in the file is a newline, then that line is not read. So, for instance, an empty file is considered to have 0 lines, according to TextFile.readln. Weird.).
	{
		writeln(line);
		lineCounter++;
	}
	myTextFile.close();
	//writeln("read " + lineCounter + " lines.");

    forgetCurrentCoordinates();
}

function steadyRest_engage(diameter, returnImmediately){
	if (typeof returnImmediately == 'undefined') {returnImmediately = false;}
	writeln("");
	writeln("");
	// ought to move to a convenient position here.
	// writeln("G0 Z1.7 (go to safe z)");
	// writeln("G0 X-8 Y53 (traverse laterally to a position where the spindle won't interfere with your hands reaching into the machine to engage the steady rest.)");
	// writeln("M5 (turn off spindle)");
	// writeln("M9 (turn off dust collector)");
	// writeln("(>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<)");
	// writeln("(>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<)");
	// writeln("(MIKE, ENGAGE THE STEADY REST.  THEN PRESS 'RESUME')");
	// writeln("(>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<)");
	// writeln("(>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<)");
	// writeln("M0"); 
	// writeln("M3 (turn on spindle)");
	// writeln("M8 (turn on dust collector)");	
	
	// writeln("(>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<)");
	// writeln("(>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<)");
	// writeln("(NOW DRIVING THE STEADYREST TO DIAMETER: " + diameter +  "inches )");
	// writeln("(>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<)");
	// writeln("(>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<)");

writeBlock(mFormat.format(203), param1Format.format(diameter), (returnImmediately ? param2Format.format(1) : ""),  {trailingComment: "DRIVE STEADYREST TO DIAMETER=" + diameter + " " + (returnImmediately ? "and return immediately" : "and wait for steadyrest move to finish before proceeding")});
}

function steadyRest_home(){
	writeln("");
	writeln("");
	writeBlock(mFormat.format(204),  {trailingComment: "HOME THE STEADYREST"});
}

function onAction(value){  //this onAction() function is not a standard member function of postProcessor, but my own invention.
		eval(value); //dirt simple - just execute the string as javascript in this context.  //ought to catch errors here.
}

/*This function reads the specified json file and returns the object contained therein.*/
function getObjectFromJsonFile(pathOfJsonFile){
	var myTextFile = new TextFile(pathOfJsonFile,false,"ansi");
	var lineCounter = 0;
	var line;
	var fileContents = "";
	while(!function(){try {line=myTextFile.readln(); eof = false;} catch(error) {eof=true;} return eof;}())  //if the final line is empty (i.e. if the last character in the file is a newline, then that line is not read. So, for instance, an empty file is considered to have 0 lines, according to TextFile.readln. Weird.).
	{
		fileContents += line;
		lineCounter++;
	}
	myTextFile.close();
	//writeln("read " + lineCounter + " lines.");
	
	return JSON.parse(fileContents);
}

function getMethods(obj){
    var res = [];
    for(var m in obj) {
        if(typeof obj[m] == "function") {
            res.push(m)
        }
    }
    return res;
}

function reconstruct(obj){
    var names = Object.getOwnPropertyNames(obj);
	var res = {};
    for each (var name in names) {		
		if(typeof obj[name] == "function") {
            res[name] = obj[name].toSource();
        } else {
		    res[name] = JSON.stringify(obj[name]);
		}
		
    }
    return res;
}

function vectorToArray(v){
    return [v.x,v.y,v.z];
}

function dumpObjectToString(obj,name){
	var message = "";
    message += "" + "\n";
	message += "JSON.stringify(getMethods("+name+"),null,'\t')   >>>>>>>>>>>>>>" + "\n";
	message += JSON.stringify(getMethods(obj),null,'\t') + "\n";

	message += "" + "\n";
	message += "JSON.stringify("+name+".keys,null,'\t')   >>>>>>>>>>>>>>" + "\n";
	message += JSON.stringify(obj.keys,null,'\t') + "\n";

	message += "" + "\n";
	message += "JSON.stringify(reconstruct("+name+"),null,'\t')   >>>>>>>>>>>>>>" + "\n";
	message += JSON.stringify(reconstruct(obj),null,'\t') + "\n";

	message += "" + "\n";
	message += "JSON.stringify(Object.getOwnPropertyNames("+name+"),null,'\t')   >>>>>>>>>>>>>>" + "\n";
	message += JSON.stringify(Object.getOwnPropertyNames(obj),null,'\t') + "\n";
    return message;
}


function logDebug(message, tabLevel){
    if(debugging){
        if(tabLevel === undefined){tabLevel = 0;}
        writeln(message.split("\n").map(function(line){return ";  " + repeatStringNumTimes("\t", tabLevel)  + line;}).join("\n"));
    }
}

function fileGetContents(pathOfFile){
    lines = [];
    var myTextFile = new TextFile(pathOfFile,false,"ansi");
	var line;
	while(!function(){try {line=myTextFile.readln(); eof = false;} catch(error) {eof=true;} return eof;}())  //if the final line is empty (i.e. if the last character in the file is a newline, then that line is not read. So, for instance, an empty file is considered to have 0 lines, according to TextFile.readln. Weird.).
	{
		lines.push(line);
	}
	myTextFile.close();
    return lines.join("\n");
}

//thanks to https://medium.freecodecamp.org/three-ways-to-repeat-a-string-in-javascript-2a9053b93a2d
function repeatStringNumTimes(string, times) {
  var repeatedString = "";
  while (times > 0) {
    repeatedString += string;
    times--;
  }
  return repeatedString;
}

//this function works around the fact that the % operator returns negative result when the input is negative, which we do not want.
function mod(x,n){
    return (x % n + n) % n;
}


function getSectionParameters(section){
    var parametersMap = {};
    parameterNames.map(function(name){if(section.hasParameter(name)){parametersMap[name] = section.getParameter(name);}});
    return parametersMap;
}

function getGlobalParameters(){
    var parametersMap = {};
    parameterNames.map(function(name){if(hasParameter(name)){parametersMap[name] = getParameter(name);}});
    return parametersMap;
}


//copied from the latest (as of 2019-04-04) out-of-the-box mach3 post processor from hsmworks
//added a call to forgetCoordinates() at the end of the function body.
/** Output block to do safe retract and/or move to home position. */
//this function takes a variable number of arguments each one of the constants X, Y, or Z (which have values 0, 1, and 2, respectively.)
//this function issues g-code commands (G53 and/or G28) whose coordinates are interpreted as being in the absolute machine frame. -- the current offset is irrelevant.
function writeRetract() {
  // initialize routine
  var _xyzMoved = new Array(false, false, false);
  var _useG28 = properties.useG28; // can be either true or false

  // check syntax of call
  if (arguments.length == 0) {
    error(localize("No axis specified for writeRetract()."));
    return;
  }
  for (var i = 0; i < arguments.length; ++i) {
    if ((arguments[i] < 0) || (arguments[i] > 2)) {
      error(localize("Bad axis specified for writeRetract()."));
      return;
    }
    if (_xyzMoved[arguments[i]]) {
      error(localize("Cannot retract the same axis twice in one line"));
      return;
    }
    _xyzMoved[arguments[i]] = true;
  }
  
  // special conditions
  if (!_useG28 && _xyzMoved[2] && (_xyzMoved[0] || _xyzMoved[1])) { 
    //if we are not using G28 and we are supposed to retract Z and we are supposed to retract at least one of X or Y...
  // Z doesn't use G53
    error(localize("You cannot move home in XY & Z in the same block."));
    return;
  }
  
  //I am not sure I agree with the below idea that we should not make any attempt to retract if we are trying to retract Z without using G28.
  if (_xyzMoved[2] && !_useG28) {
      // if we are not using G28 and we are supposed to retract Z...
      //for some reason, the standard hsmworks post-processor does "return" in this situation - thereby not attempting any motion in the
      // case where we are trying to retract the z axis and useG28 is false. I suppose this makes sense, from a standpoint of maximum safety --
      // if there is no defined safe z position (i.e. no G28 (or we are forbidden from using G28)), then it is better to not move to 
      // a hard-coded z position, which would be the only other option.
    return;
  }

  // define home positions
  var _xHome;
  var _yHome;
  var _zHome;
  if (_useG28) {
    _xHome = 0;
    _yHome = 0;
    _zHome = 0;
  } else {
    _xHome = machineConfiguration.hasHomePositionX() ? machineConfiguration.getHomePositionX() : 0;
    _yHome = machineConfiguration.hasHomePositionY() ? machineConfiguration.getHomePositionY() : 0;
    _zHome = machineConfiguration.getRetractPlane();
  }

  // format home positions
  var words = []; // store all retracted axes in an array
  for (var i = 0; i < arguments.length; ++i) {
    // define the axes to move
    switch (arguments[i]) {
    case X:
      if (machineConfiguration.hasHomePositionX() || properties.useG28) {
        words.push("X" + xyzFormat.format(_xHome));
      }
      break;
    case Y:
      if (machineConfiguration.hasHomePositionY() || properties.useG28) {
        words.push("Y" + xyzFormat.format(_yHome));
      }
      break;
    case Z:
      words.push("Z" + xyzFormat.format(_zHome));
      retracted = true;
      break;
    }
  }

  // output move to home
  if (words.length > 0) {
    if (_useG28) {
      gAbsIncModal.reset();
      writeBlock(gFormat.format(28), gAbsIncModal.format(91), words);
      writeBlock(gAbsIncModal.format(90), {trailingComment: "position mode: absolute"});
    } else {
      gMotionModal.reset();
      writeBlock(gAbsIncModal.format(90), gFormat.format(53), gMotionModal.format(0), words);
    }

    // force any axes that move to home on next block
    if (_xyzMoved[0]) {
      xOutput.reset();
    }
    if (_xyzMoved[1]) {
      yOutput.reset();
    }
    if (_xyzMoved[2]) {
      zOutput.reset();
    }
  }
  forgetCurrentCoordinates(arguments);
}

// //this function scans through all the records of the specified section looking for records that define parameters.  Collects all the parameter names and values into a map, which it returns.
//DOESN't SEEM to work -- all the records that I suspect contain paramters through an exception when we try to get them via section.getRecord()
// function getSectionParameters(section){
    // var parametersMap = {};

    // for(var i = 0; i<= section.getNumberOfRecords(); i++){
        // var thisRecord;
        // thisRecord = null;
        // try{thisRecord = section.getRecord(i);} catch(e) {logDebug("encounterd an exception when attempting to access record " + i + ": " + e);}
        // if(thisRecord && thisRecord.isParameter()){
            // logDebug("record " + i + " is a parameter.");
            // parametersMap[thisRecord.getParameterName()] = thisRecord.getParameterValue()
        // }
    // }
    // return parametersMap;
// }

