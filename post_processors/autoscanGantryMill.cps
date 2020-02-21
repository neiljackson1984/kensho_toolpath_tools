/**
  Mach3Mill post processor configuration. for HSMWorks.
  
  

*/
// include(findFile("decimal.js"));
include("decimal.js");
description = "Autoscan Gantry Mill";
vendor = "Autoscan";
vendorUrl = "http://autoscaninc.com";
legal = "";
description="This is the post-processor description. Lorem Ipsum dolorem sit amet. ";
certificationLevel = 2;
//minimumRevision = 24000;

extension = "nc";
setCodePage("ascii");

var debugging = false;

/*
Boolean mapWorkOrigin 
Specifies that the section origin should be mapped to (0, 0, 0). When disabled the post is responsible for handling the section origin. By default this is enabled. 
*/
mapWorkOrigin =true;

/*
Boolean mapToWCS 
Specifies that the section work plane should be mapped to the WCS. When disabled the post is responsible for handling the WCS and section work plane. By default this is enabled. 
*/
mapToWCS = true;

//debugMode=true;
tolerance = spatial(0.002, MM);

minimumChordLength = spatial(0.01, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(180);
allowHelicalMoves = false;
allowedCircularPlanes = 0;  //undefined; // set to 0 to forbid any circular motion and to undefined to allow circular motion on any plane

// user-defined properties
properties = {
  useG28: false, // disable to avoid G28 output for safe machine retracts - when disabled you must manually ensure safe retracts
  useM6: false, // disable to avoid M6 output - preload is also disabled when M6 is disabled
  useG43WithM6ForToolchanges: true, //if useM6 is true, then whenever we output an M6, we will immediately afterward output a G43 to enable the tool length offset for the newly selected tool.
  preloadTool: false, // preloads next tool on tool change if any
  useRadius: true // specifies that arcs should be output using the radius (R word) instead of the I, J, and K words.
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

var nFormat             =  createFormat({prefix:"N", decimals:0});
var gFormat             =  createFormat({prefix:"G", decimals:1});
var mFormat             =  createFormat({prefix:"M", decimals:0});
var hFormat             =  createFormat({prefix:"H", decimals:0});
var pFormat             =  createFormat({prefix:"P", decimals:(unit == MM ? 3 : 4), scale:0.5});
var param1Format        =  createFormat({prefix:"P", decimals:7});  //this format spec is used for the argument that mach3 scripts called from gcode will read as Param1()
var param2Format        =  createFormat({prefix:"Q", decimals:7});  //this format spec is used for the argument that mach3 scripts called from gcode will read as Param2()
var param3Format        =  createFormat({prefix:"R", decimals:7});  //this format spec is used for the argument that mach3 scripts called from gcode will read as Param3()
var xyzFormat           = createFormat({decimals:(unit == MM ? 3 : 4), forceDecimal:true});
var rFormat             = xyzFormat; // radius
var abcFormat           = createFormat({decimals:3, forceDecimal:true, scale:DEG});
var feedFormat          = createFormat({decimals:(unit == MM ? 0 : 1), forceDecimal:true});
var toolFormat          = createFormat({decimals:0});
var rpmFormat           = createFormat({decimals:0});
var secondsFormat       = createFormat({decimals:3, forceDecimal:true}); // seconds - range 0.001-99999.999
var millisecondsFormat  = createFormat({decimals:0}); // milliseconds // range 1-9999
var taperFormat         = createFormat({decimals:1, scale:DEG});

var xOutput             = createVariable({prefix:"X"}, xyzFormat);
var yOutput             = createVariable({prefix:"Y"}, xyzFormat);
var zOutput             = createVariable({prefix:"Z"}, xyzFormat);
var aOutput             = createVariable({prefix:"A"}, abcFormat);
var bOutput             = createVariable({prefix:"B"}, abcFormat);
var cOutput             = createVariable({prefix:"C"}, abcFormat);
var feedOutput          = createVariable({prefix:"F"}, feedFormat);
var sOutput             = createVariable({prefix:"S", force:true}, rpmFormat);
var pOutput             = createVariable({}, pFormat);

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


// collected state
var currentWorkOffset;

/**
  Writes the specified block.
*/
function writeBlock() {
    writeWords(arguments);
}

/**
  Output a comment.
*/
function writeComment(text) {
  writeln("(" + filterText(String(text).toUpperCase(), permittedCommentChars) + ")");
}



function onOpen() {
  optimizeMachineAngles2(TCP_MODE__MAP_TOOL_TIP_POSITION); // map tip mode  //in this mode, the coordinates that appear as numbers in the gcode are the coordinates of the tip in the machine frame.  This is what we want.	
  
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
  
  if (true) {// check for duplicate tool number
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
  
  gAbsIncModal.reset(); //force output on next invocation on gAbsIncModal.format()
  writeBlock(gAbsIncModal.format(90), "(position mode: absolute)");

  gFeedModeModal.reset(); //force output on next invocation on gFeedModeModal.format()
  writeBlock(gFeedModeModal.format(94), "(feedrate mode: length per time)");

  writeBlock(gFormat.format(91.1), "(arc center mode: incremental)");

  writeBlock(gFormat.format(40), "(cancel cutter compensation)");

  writeBlock(gFormat.format(49), "(cancel tool-length offset)");

  gPlaneModal.reset(); //force output on next invocation on gPlaneModal.format()
  writeBlock(gPlaneModal.format(17), "(plane for circular moves: XY plane)");
  
  writeBlock(gFormat.format(49), "(cancel tool-length offset)");
  
  velocityBlendingModeModal.reset(); //force output on next invocation on velocityBlendingModeModal.format()
  writeBlock(velocityBlendingModeModal.format(64), "(constant velocity mode)");

  switch (unit) {
     case IN:
       writeBlock(gUnitModal.format(20), "(unit mode: inches)");
       break;
     case MM:
       writeBlock(gUnitModal.format(21), "(unit mode: millimeters)");
       break;
  }
}

function onComment(message) {
  var comments = String(message).split(";");
  for (comment in comments) {
    writeComment(comments[comment]);
  }
}

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
	if(debugging){writeln("setWorkPlane("+abc+") was called.");}
  if (!machineConfiguration.isMultiAxisConfiguration()) {
    writeComment("setWorkPlane() is finished. machineConfiguration.isMultiAxisConfiguration() is false, so we did not need to do anything.");
    return; // ignore
  }

  // if currentWorkPlaneABC is defined AND the argument, abc, is the same as currentWorkPlaneABC, then we do not need to do anything, so return; else proceed.
  if (!(
		(currentWorkPlaneABC == undefined) ||
        abcFormat.areDifferent(abc.x, currentWorkPlaneABC.x) ||
        abcFormat.areDifferent(abc.y, currentWorkPlaneABC.y) ||
        abcFormat.areDifferent(abc.z, currentWorkPlaneABC.z)
	)) {
    return; // no change
    writeComment("setWorkPlane() is finished. We did not need to do anything.");

  }

  
  writeBlock(
    gMotionModal.format(0),
    conditional(machineConfiguration.isMachineCoordinate(0), "A" + abcFormat.format(abc.x)),
    conditional(machineConfiguration.isMachineCoordinate(1), "B" + abcFormat.format(abc.y)),
    conditional(machineConfiguration.isMachineCoordinate(2), "C" + abcFormat.format(abc.z))
  );
  

  currentWorkPlaneABC = abc;
  writeComment("setWorkPlane() is finished.");
}

var closestABC = false; // choose closest machine angles
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
      + conditional(machineConfiguration.isMachineCoordinate(0), " A" + abcFormat.format(abc.x))
      + conditional(machineConfiguration.isMachineCoordinate(1), " B" + abcFormat.format(abc.y))
      + conditional(machineConfiguration.isMachineCoordinate(2), " C" + abcFormat.format(abc.z))
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
    var R = machineConfiguration.getRemainingOrientation(abc, W);
    setRotation(R);
  }
  
  return abc;
}

function onSection() {

   if(debugging) {
   	writeln("currentSection.workPlane: " + currentSection.workPlane);
   	writeln("currentSection.getWorkPlane(): " + currentSection.getWorkPlane());
   	dump(new Record(),"Record()");
   	dump({a:25,b:35},"{a:25,b:35}");
   	dump(this,"this");
   }

  var insertToolCall = 
       isFirstSection() 
    || currentSection.getForceToolChange()
    || (tool.number != getPreviousSection().getTool().number);
  
  var retracted = false; // specifies that the tool has been retracted to the safe plane
  var newWorkOffset = isFirstSection() || (getPreviousSection().workOffset != currentSection.workOffset); // work offset changes
  var newWorkPlane = isFirstSection() ||
    !isSameDirection(getPreviousSection().getGlobalFinalToolAxis(), currentSection.getGlobalInitialToolAxis());
  if (insertToolCall || newWorkOffset || newWorkPlane) {
    
    if (properties.useG28) {
      // retract to safe plane
      retracted = true;
      writeBlock(gFormat.format(28), gAbsIncModal.format(91), "Z" + xyzFormat.format(0)); // retract
      writeBlock(gAbsIncModal.format(90));
      zOutput.reset();
    }
  }

  writeln("");

  if (hasParameter("operation-comment")) {
    var comment = getParameter("operation-comment");
    if (comment) {
      writeComment(comment);
    }
  }

  if (insertToolCall) {
    forceWorkPlane();
    
    onCommand(COMMAND_STOP_SPINDLE);
    onCommand(COMMAND_COOLANT_OFF);


    if (tool.number > 256) {
      warning(localize("Tool number exceeds maximum value."));
    }

    if (properties.useM6) {
      writeBlock("T" + toolFormat.format(tool.number), mFormat.format(6), "(the current tool is now tool " + tool.number + ".perform a tool change operation" + ")");
	  	//might consider emitting a "G43" here to turn on the tool offset.
		if(properties.useG43WithM6ForToolchanges)
		{
			writeBlock(gFormat.format(43) + " (enable tool length offset)");
		}
    } else {
      writeBlock("T" + toolFormat.format(tool.number), "(the current tool is now tool " + tool.number + ".)");
    }

	
    if (tool.comment) {
      writeComment(tool.comment);
    }


    if (properties.preloadTool && properties.useM6) {
      var nextTool = getNextTool(tool.number);
      if (nextTool) {
        writeBlock("T" + toolFormat.format(nextTool.number));
      } else {
        // preload first tool
        var section = getSection(0);
        var firstToolNumber = section.getTool().number;
        if (tool.number != firstToolNumber) {
          writeBlock("T" + toolFormat.format(firstToolNumber));
        }
      }
    }
  }
  
  writeBlock(sOutput.format(tool.spindleRPM), "(set spindle speed to " + tool.spindleRPM + " RPM)");
  onCommand(COMMAND_START_SPINDLE);
  
  velocityBlendingModeModal.reset(); //force output on next invocation on velocityBlendingModeModal.format()
  writeBlock(velocityBlendingModeModal.format(64), "(constant velocity mode)");


  // wcs
  var workOffset = currentSection.workOffset;
  if (workOffset == 0) {
    warning(localize("Work offset has not been specified. Using G54 as WCS."));
    workOffset = 1;
  }
  if (workOffset > 0) {
    if (workOffset > 6) {
      var p = workOffset; // 1->... // G59 P1 is the same as G54 and so on
      if (p > 254) {
        error(localize("Work offset out of range."));
      } else {
        if (workOffset != currentWorkOffset) {
          writeBlock(gFormat.format(59), "P" + p); // G59 P
          currentWorkOffset = workOffset;
        }
      }
    } else {
      if (workOffset != currentWorkOffset) { 
        writeBlock(gFormat.format(53 + workOffset)); // G54->G59
        currentWorkOffset = workOffset;
      }
    }
  }

  forceXYZ();


  writeBlock("M202", "(add a multiple of 360 to the G92 offset of the rotary coordinate )"); //anti-windup reset of rotary coordinate.

  if (machineConfiguration.isMultiAxisConfiguration()) { // use 5-axis indexing for multi-axis mode
    // set working plane after datum shift

    var abc = new Vector(0, 0, 0);
    if (currentSection.isMultiAxis()) {
      forceWorkPlane();
      cancelTransformation();
    } else {
      abc = getWorkPlaneMachineABC(currentSection.workPlane);
    }
    setWorkPlane(abc);
  } else { // pure 3D
    var remaining = currentSection.workPlane;
    if (!isSameDirection(remaining.forward, new Vector(0, 0, 1))) {
      error(localize("Tool orientation is not supported."));
      return;
    }
    setRotation(remaining);
  }

  // set coolant after we have positioned at Z
  {
    var c = mapCoolantTable.lookup(tool.coolant);
    if (c) {
      writeBlock(mFormat.format(c), "(turn on coolant)");
    } else {
      warning(localize("Coolant not supported."));
    }
  }

  forceAny();
  gMotionModal.reset();

  var initialPosition = getFramePosition(currentSection.getInitialPosition());
  if (!retracted) {
    writeBlock(gMotionModal.format(0), zOutput.format(initialPosition.z));
	  if(debugging){writeln("RETRACTED");}
    }

  if (insertToolCall || retracted) {
    var lengthOffset = tool.lengthOffset;
    if (lengthOffset > 256) {
      error(localize("Length offset out of range."));
      return;
    }

    gMotionModal.reset();
    writeBlock(gPlaneModal.format(17));
    
    if (!machineConfiguration.isHeadConfiguration()) {
      writeBlock(
        gAbsIncModal.format(90),
        gMotionModal.format(0), xOutput.format(initialPosition.x), yOutput.format(initialPosition.y)
      );
      writeBlock(gMotionModal.format(0), gFormat.format(43), zOutput.format(initialPosition.z), hFormat.format(lengthOffset));
    } else {
      writeBlock(
        gAbsIncModal.format(90),
        gMotionModal.format(0),
        gFormat.format(43), xOutput.format(initialPosition.x),
        yOutput.format(initialPosition.y),
        zOutput.format(initialPosition.z), hFormat.format(lengthOffset)
      );
    }
  } else {
    writeBlock(
      gAbsIncModal.format(90),
      gMotionModal.format(0),
      xOutput.format(initialPosition.x),  //THIS WILL HAVe TO BE FIXED TO WORK WITH THE NEW ANGLE-AWARE ONLINEAR FUNCTION. --NEED SINGLE UNIFIED MOTION FUNCTION.
      yOutput.format(initialPosition.y)
    );
  }
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
  writeBlock(sOutput.format(spindleSpeed));
}

function onCycle() {
  writeBlock(gPlaneModal.format(17));
}

function getCommonCycle(x, y, z, r) {
  forceXYZ();
  return [xOutput.format(x), yOutput.format(y),
    zOutput.format(z),
    "R" + xyzFormat.format(r)];
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

var pendingRadiusCompensation = -1;

function onRadiusCompensation() {
  pendingRadiusCompensation = radiusCompensation;
}

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

function anglesToRevolutionRemainder(x) {
//x is expected be a Vector
return new Vector(
   (x.getX() % (2*Math.PI))/(2*Math.PI),
   (x.getY() % (2*Math.PI))/(2*Math.PI),
   (x.getZ() % (2*Math.PI))/(2*Math.PI)
);

}

//diagnostic function to figure out what the hell HSMWorks is doing
function reportPosition()
{
  if(!getRotation().isIdentity()){
     writeln("getRotation():" + (getRotation().isIdentity() ? "(identity)" : getRotation()));
  }

  if(!getTranslation().isZero()){
    writeln("getTranslation():" + (getTranslation().isZero() ? "(zero)" :  getTranslation()));
    
  }

  // try {writeln("getPosition(): " + getPosition());} catch(e){} //{writeln("getPosition() failed");}
  // try {writeln("getEnd(): " + getEnd());} catch(e){} //{writeln("getEnd() failed");}
  // try {writeln("getDirection(): " + getDirection());} catch(e){} //{writeln("getDirection() failed");}
  writeln("getCurrentPosition(): " + getCurrentPosition());
  // writeln("getCurrentGlobalPosition(): " + getCurrentGlobalPosition());
  writeln("getCurrentDirection(): " + getCurrentDirection());
  writeln("anglesToRevolutionRemainder(getCurrentDirection()): " + anglesToRevolutionRemainder(getCurrentDirection()));
  // writeln("getPositionU(0): " + getPositionU(0));
  // writeln("getPositionU(0.9999): " + getPositionU(0.9999));
  // writeln("getPositionU(1): " + getPositionU(1));
  // try {writeln("getFramePosition(getCurrentPosition()): " + getFramePosition(getCurrentPosition()));} catch(e){}
  // try {writeln("getFrameDirection(getCurrentDirection()): " + getFrameDirection(getCurrentDirection()));} catch(e){}
  writeln("getMachineConfiguration().getPosition(getCurrentPosition(), getCurrentDirection()): " + getMachineConfiguration().getPosition(getCurrentPosition(), getCurrentDirection()));
  writeln("getMachineConfiguration().getDirection(getCurrentDirection()): " + getMachineConfiguration().getDirection(getCurrentDirection()) + " (length: " + norm(getMachineConfiguration().getDirection(getCurrentDirection())) + ")");
  writeln("currentSection.isOptimizedForMachine(): " + currentSection.isOptimizedForMachine());
  writeln("currentSection.getOptimizedTCPMode(): " + currentSection.getOptimizedTCPMode());
  writeln("currentSection.getWorkPlane(): " + currentSection.getWorkPlane());
  // try {writeln("start: " + start);} catch(e){writeln("start threw exception");}
  // try {writeln("end: " + end);} catch(e){writeln("end threw exception");}
  
  // writeln("getMachineConfiguration().getDirection(new Vector(0,0,0)): " + getMachineConfiguration().getDirection(new Vector(0,0,0)));
  // writeln("getMachineConfiguration().getDirection(new Vector(90,0,0)): " + getMachineConfiguration().getDirection(new Vector(90,0,0)));
  // writeln("getMachineConfiguration().getDirection(new Vector(Math.PI/2,0,0)): " + getMachineConfiguration().getDirection(new Vector(Math.PI/2,0,0)));
  // getMachineConfiguration().getDirection() expects an argument in units of radians, which is as it should be.

  // var direction = 
  //    Vector(
  //        getMachineConfiguration().getDirection(getCurrentDirection()).getX(),
  //        getMachineConfiguration().getDirection(getCurrentDirection()).getY(),
  //        getMachineConfiguration().getDirection(getCurrentDirection()).getZ()
  //    );
  
  // dump(direction, "direction");
  // writeln("typeof(getMachineConfiguration().getDirection(getCurrentDirection())): " + typeof(getMachineConfiguration().getDirection(getCurrentDirection())));
  // dump(getMachineConfiguration().getDirection(getCurrentDirection()), "getMachineConfiguration().getDirection(getCurrentDirection())");
  //writeln("getCurrentNCLocation(): " + getCurrentNCLocation());
}


function onRapid(_x, _y, _z) {
	if(debugging){
	  writeln("");
	  writeln("onRapid("+_x+", "+_y+", "+_z+") was called)");
	  reportPosition();
	}
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  if (x || y || z) {
    if (pendingRadiusCompensation >= 0) {
      error(localize("Radius compensation mode cannot be changed at rapid traversal."));
      return;
    }
    writeBlock(gMotionModal.format(0), x, y, z);
    feedOutput.reset();
  }
}

function onLinear(_x, _y, _z, feed) {
	if(debugging){
	  writeln("");
	  writeln("onLinear("+_x+", "+_y+", "+_z+", "+feed+") was called)");
	  reportPosition();
	}
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  var f = feedOutput.format(feed);
  if (x || y || z) {
    if (pendingRadiusCompensation >= 0) {
      pendingRadiusCompensation = -1;
      writeBlock(gPlaneModal.format(17));
      switch (radiusCompensation) {
      case RADIUS_COMPENSATION_LEFT:
        pOutput.reset();
        writeBlock(gMotionModal.format(1), pOutput.format(tool.diameter), gFormat.format(41), x, y, z, f);
        break;
      case RADIUS_COMPENSATION_RIGHT:
        pOutput.reset();
        writeBlock(gMotionModal.format(1), pOutput.format(tool.diameter), gFormat.format(42), x, y, z, f);
        break;
      default:
        writeBlock(gMotionModal.format(1), gFormat.format(40), x, y, z, f);
      }
    } else {
      writeBlock(gMotionModal.format(1), x, y, z, f);
    }
  } else if (f) {
    if (getNextRecord().isMotion()) { // try not to output feed without motion
      feedOutput.reset(); // force feed on next line
    } else {
      writeBlock(gMotionModal.format(1), f);
    }
  }
}

function onRapid5D(_x, _y, _z, _a, _b, _c) {
if(debugging){
  writeln("");
	writeln("onRapid5D("+_x+", "+_y+", "+_z+", "+_a+", "+_b+", "+_c+") was called)");
    reportPosition();
  }
  
	//commented out the following lines because they were preventing toolpath from being made
  // if (!currentSection.isOptimizedForMachine()) {
    // error(localize("This post configuration has not been customized for 5-axis simultaneous toolpath."));
    // return;
  // } 
  if (pendingRadiusCompensation >= 0) {
    error(localize("Radius compensation mode cannot be changed at rapid traversal."));
    return;
  }
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  var a = aOutput.format(_a);
  var b = bOutput.format(_b);
  var c = cOutput.format(_c);
  writeBlock(gMotionModal.format(0), x, y, z, a, b, c, "(" + movementToString(movement) + ")");
  feedOutput.reset();
}

function onLinear5D(_x, _y, _z, _a, _b, _c, feed) {
  var startPosition = (currentSection.getOptimizedTCPMode() == 0 ?   getCurrentPosition() : getMachineConfiguration().getPosition( getCurrentPosition(),   getCurrentDirection()   ) );
  var endPosition   = (currentSection.getOptimizedTCPMode() == 0 ? new Vector(_x, _y, _z) : getMachineConfiguration().getPosition( new Vector(_x, _y, _z), new Vector(_a, _b, _c)  ) );
  var distance = Vector.getDistance(startPosition, endPosition);
  var duration = distance/feed; //the duration of the move (in minutes)
  if(duration==0){duration = Math.pow(10,-8)};  //if the duration of the move is zero (which would happen if distance were zero, then set duration to a very small, finitie, number, so that 1/duration will be finite.)
  
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
    try {writeln("getFeedRate(): "   + getFeedRate());} catch(e){writeln("getFeedRate() threw exception.");}
	  }
	//commented out the following lines because they were preventing toolpath from being made
  // if (!currentSection.isOptimizedForMachine()) {
    // error(localize("This post configuration has not been customized for 5-axis simultaneous toolpath."));
    // return;
  // }
  if (pendingRadiusCompensation >= 0) {
    error(localize("Radius compensation cannot be activated/deactivated for 5-axis move."));
    return;
  }
  // getCurrentPosition() and getCurrentDirection() return the position and orientation of where we are coming from.
  // The line of gcode that we output here will move the machine from the point described by getCurrentPosition() to
  // the point described by _x, _y, _z, _a, _b, _c.
  
  

  // var x = xOutput.format(_x);
  // var y = yOutput.format(_y);
  // var z = zOutput.format(_z);
  // var a = aOutput.format(_a);
  // var b = bOutput.format(_b);
  // var c = cOutput.format(_c);
  // var f = feedOutput.format(feed);
  //writeBlock(gMotionModal.format(1), x, y, z, a, b, c, f, "(" + movementToString(movement) + ")");
  
  //forcing the output of G93, G1, and inverse time feed rate may not be strictly necessary, but when it comes to using inverse time feedrate mode, I do not want to take any chances.
  feedOutput.format(1/duration);
  gMotionModal.reset(); //force to output motion mode (i.e. G1 or G0) on next call to gMotionModal.format();
  gFeedModeModal.reset(); //force to output the feedMode on next cal to gFeedModeModal.format();
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
    // feedOutput.format(1/duration),  //TODO: format the F word to achieve a specified relative precision (i.e. specify the number of signifricant figures, rather than the number of decimal places. The reason for this is that with inverse ti9me feed rate, we could conceivably ending up needing to specify some very small F values (for long duration moves).)
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

var mapCommand = {
  COMMAND_STOP:0,
  COMMAND_OPTIONAL_STOP:1,
  COMMAND_END:2,
  COMMAND_SPINDLE_CLOCKWISE:3,
  COMMAND_SPINDLE_COUNTERCLOCKWISE:4,
  COMMAND_STOP_SPINDLE:5,
  COMMAND_ORIENTATE_SPINDLE:19,
  COMMAND_LOAD_TOOL:6,
  COMMAND_COOLANT_ON:8, // flood
  COMMAND_COOLANT_OFF:9
};

function onCommand(command) {
  
  //writeln(">>>>>>>>>>>>>>>>>  onCommand( " + command +  " ) ");
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
  var mcode = mapCommand[stringId];
  if (mcode != undefined) {
    writeBlock(mFormat.format(mcode),"(" + stringId + ")");
  } else {
    onUnsupportedCommand(command);
  }
  //writeln(">>>>>>>>>>>>>>>>>  endCommand ");
}

/*
Inserts an external file into the gcode output.  the path is relative to the output gcode file (or can also be absolute).
If the file estension is "php", this is a special case: in this case, the php file is executed and the stdout is included in 
the output gcode file.
*/
function includeFile(path)
{
	writeln("(>>>>>>>>>>>>>>>>>  file to be included: " + path + ")"); //temporary behavior for debugging.
	//if path is not absolute, it will be assumed to be relative to the folder where the output file is being placed.
	
	var absolutePath = 
		FileSystem.getCombinedPath(
			FileSystem.getFolderPath(getOutputPath()) ,
			path
		);
	
	var fileExtension = FileSystem.getFilename(path).replace(FileSystem.replaceExtension(FileSystem.getFilename(path)," ").slice(0,-1),""); //this is a bit of a hack to work around the fact that there is no getExtension() function.  Strangely, FileSystem.replaceExtension strips the period when, and only when, the new extension is the emppty string.  I ought to do all of this with RegEx.  //bizarrely, replaceExtension() evidently regards the extension of the file whose name is "foo" to be "foo" --STUPID (but this weirdness won't affect my current project.)
	
	// //writeln("getOutputPath():\""+getOutputPath()+"\"");
	// //writeln("FileSystem.getFilename(path):\"" + FileSystem.getFilename(path) + "\"");
	// writeln("fileExtension:\""+fileExtension+"\"");
	// writeln("absolutePath:\"" + absolutePath + "\"");
	// writeln("FileSystem.getTemporaryFolder():\"" + FileSystem.getTemporaryFolder() + "\"");
	var fileToBeIncludedVerbatim;
	var returnCode;
	switch(fileExtension.toLowerCase()){ //FIX
		case "php" :
			//FileSystem.getTemporaryFile() was not working, until I discovered that the stupid thing was trying to create a file in a non-existent temporary folder.
			// Therefore, I must first ensure that the temporary folder exists.  STUPID!
			if(! FileSystem.isFolder(FileSystem.getTemporaryFolder())){FileSystem.makeFolder(FileSystem.getTemporaryFolder());}
			var tempFile = FileSystem.getTemporaryFile("");
			//writeln("tempFile:\""+tempFile+"\"");
			returnCode = execute("cmd", "/c php \""+absolutePath+"\" > \""+tempFile+"\"", false, ""); //run it through php and collect the output
			//writeln("returnCode:"+returnCode);
			fileToBeIncludedVerbatim = tempFile;
			break;
		
		default :
			fileToBeIncludedVerbatim = absolutePath;
			break;
	
	}
	
	var myTextFile = new TextFile(fileToBeIncludedVerbatim,false,"ansi");
	var lineCounter = 0;
	var line;
	while(!function(){try {line=myTextFile.readln(); eof = false;} catch(error) {eof=true;} return eof;}())  //if the final line is empty (i.e. if the last character in the file is a newline, then that line is not read. So, for instance, an empty file is considered to have 0 lines, according to TextFile.readln. Weird.).
	{
		writeln(line);
		lineCounter++;
	}
	myTextFile.close();
	//writeln("read " + lineCounter + " lines.");
}

function steadyRest_engage(diameter, returnImmediately)
{
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

	writeBlock(mFormat.format(203), param1Format.format(diameter), (returnImmediately ? param2Format.format(1) : ""), "( DRIVE STEADYREST TO DIAMETER=" + diameter + " " + (returnImmediately ? "and return immediately" : "and wait for steadyrest move to finish before proceeding") + ")");

}

function steadyRest_home()
{
	writeln("");
	writeln("");

	writeBlock(mFormat.format(204), "( HOME THE STEADYREST )");

}

function onAction(value)  //this onAction() function is not a standard member function of postProcessor, but my own invention.
{
		eval(value); //dirt simple - just execute the string as javascript in this context.  //ought to catch errors here.
}



function onParameter(name,value)
{
	//writeln(">>>>>>>>>>>>>>>>>  onParameter(" + name + ","+ value +") ");
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

  forceAny();
}

function onClose() {
  writeln("");

  onCommand(COMMAND_COOLANT_OFF);

  if (properties.useG28) {
    writeBlock(gFormat.format(28), gAbsIncModal.format(91), "Z" + xyzFormat.format(0)); // retract
    zOutput.reset();
  }

  setWorkPlane(new Vector(0, 0, 0)); // reset working plane

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

function onPassThrough(value)
{
	writeln(value);
}


/*This function reads the specified json file and returns the object contained therein.*/
function getObjectFromJsonFile(pathOfJsonFile)
{
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




function getMethods(obj)
{
    var res = [];
    for(var m in obj) {
        if(typeof obj[m] == "function") {
            res.push(m)
        }
    }
    return res;
}


function reconstruct(obj)
{
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

function dump(obj,name)
{
	writeln("");
	writeln("JSON.stringify(getMethods("+name+"),null,'\t')   >>>>>>>>>>>>>>");
	writeln(JSON.stringify(getMethods(obj),null,'\t'));
	
	writeln("");
	writeln("JSON.stringify("+name+".keys,null,'\t')   >>>>>>>>>>>>>>");
	writeln(JSON.stringify(obj.keys,null,'\t'));
	
	writeln("");
	writeln("JSON.stringify(reconstruct("+name+"),null,'\t')   >>>>>>>>>>>>>>");
	writeln(JSON.stringify(reconstruct(obj),null,'\t'));
	
	writeln("");
	writeln("JSON.stringify(Object.getOwnPropertyNames("+name+"),null,'\t')   >>>>>>>>>>>>>>");
	writeln(JSON.stringify(Object.getOwnPropertyNames(obj),null,'\t'));
	
	
	
}



function movementToString(movement)
{
	switch (movement) {
		case MOVEMENT_RAPID             : return "MOVEMENT_RAPID";                   break;
		case MOVEMENT_LEAD_IN           : return "MOVEMENT_LEAD_IN";                 break;
		case MOVEMENT_CUTTING           : return "MOVEMENT_CUTTING";                 break;
		case MOVEMENT_LEAD_OUT          : return "MOVEMENT_LEAD_OUT";                break;
		case MOVEMENT_LINK_TRANSITION   : return "MOVEMENT_LINK_TRANSITION";         break;      
		case MOVEMENT_LINK_DIRECT       : return "MOVEMENT_LINK_DIRECT";             break;  
		case MOVEMENT_RAMP_HELIX        : return "MOVEMENT_RAMP_HELIX";              break; 
		case MOVEMENT_RAMP_PROFILE      : return "MOVEMENT_RAMP_PROFILE";            break;   
		case MOVEMENT_RAMP_ZIG_ZAG      : return "MOVEMENT_RAMP_ZIG_ZAG";            break;   
		case MOVEMENT_RAMP              : return "MOVEMENT_RAMP";                    break; 
		case MOVEMENT_PLUNGE            : return "MOVEMENT_PLUNGE";                  break; 
		case MOVEMENT_PREDRILL          : return "MOVEMENT_PREDRILL";                break;
		case MOVEMENT_EXTENDED          : return "MOVEMENT_EXTENDED";                break;
		case MOVEMENT_REDUCED           : return "MOVEMENT_REDUCED";                 break;
		case MOVEMENT_FINISH_CUTTING    : return "MOVEMENT_FINISH_CUTTING";          break;     
		case MOVEMENT_HIGH_FEED         : return "MOVEMENT_HIGH_FEED";               break;
		default: return "unknown movement";
	}
	return "unknown movement";
}
