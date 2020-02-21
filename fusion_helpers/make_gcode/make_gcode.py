#Author-Neil
#Description-Dumps user parameters to a file, ready for any post-processing scripts to digest, then involes Neil's preferred post processor (would prefer to invoke the post processor referenced in the document, but there does not appear to be any api exposure of the "nc program" object.

import adsk.core, adsk.fusion, adsk.cam, traceback
import sys, os.path
import json
import time

commandDefinition = None
toolbarControl = None

#this add in will create one command.
#Here is a unique id for the command: 
commandId = 'makeGcode1239571089741098234'
toolbarId = 'QAT' #specify the toolbar where you want to insert this command (for simplicity, we are going to insert it directly into a toolbar rather than into a panel within a toolbar.
commandResources = './resources'

# global set of event handlers to keep them referenced for the duration of the command (to prevent Python garbage collection from destroying the event handlers).
handlers = []


class makeGcodeCommandExecuteHandler(adsk.core.CommandEventHandler):
    def __init__(self):
        super().__init__()
    def notify(self, args):
        try:
            # camOutputFolder = cam.temporaryFolder
            camOutputFolder = "U:/tonfa/milling/gcode"
            # camOutputFolder = "C:/Users/Admin/Google Drive/kensho/G code"
            postConfig = "U:/tonfa/braids/hsmworks_customization/postProcessors/kenshoMaverick.cps" 
            app = adsk.core.Application.get()
            ui = app.userInterface
            command = args.firingEvent.sender
            doc = app.activeDocument
            product = doc.products.itemByProductType('CAMProductType')
            if product == None:
                g_ui.messageBox('There are no CAM operations in the active document.  This script requires the active document to contain at least one CAM operation.',
                                'No CAM Operations Exist',
                                adsk.core.MessageBoxButtonTypes.OKButtonType,
                                adsk.core.MessageBoxIconTypes.CriticalIconType)
                return
            cam = adsk.cam.CAM.cast(product)

    
            # setupsToBePosted = list(filter(lambda x: x.operationType == adsk.cam.OperationTypes.MillingOperation,   cam.setups))
            setupsToBePosted = list(
                filter(
                    lambda x: True,   
                    cam.setups
                )
            )
            # we will post all setups that contain at least one valid operation.
            # failing to do this check will cause an exception to be thrown when we try to
            # post a setup having no valid operations.
            # ui.messageBox("setupsToBePosted: " + ", ".join(map(lambda x: x.name, setupsToBePosted)))
            operationsToBeRegenerated = adsk.core.ObjectCollection.create();
            for setup in setupsToBePosted:
                for operation in setup.allOperations:
                    if not cam.checkToolpath(operation) and not operation.isSuppressed:
                        operationsToBeRegenerated.add(operation)
         
            # global generateToolpathFuture
            if operationsToBeRegenerated.count > 0:
                generateToolpathFuture = cam.generateToolpath(operationsToBeRegenerated)

                #  create and show the progress dialog while the toolpaths are being generated.
                progress = ui.createProgressDialog()
                progress.isCancelButtonShown = False
                progress.show('Toolpath Generation Progress', 'Generating Toolpaths', 0, 10)

                # Enter a loop to wait while the toolpaths are being generated and update
                # the progress dialog.
                while not generateToolpathFuture.isGenerationCompleted:
                    # since toolpaths are calculated in parallel, loop the progress bar while the toolpaths 
                    # are being generated but none are yet complete.
                    n = 0
                    start = time.time()
                    while generateToolpathFuture.numberOfCompleted == 0:
                        if time.time() - start > .125: # increment the progess value every .125 seconds.
                            start = time.time()
                            n +=1
                            progress.progressValue = n
                            adsk.doEvents()
                        if n > 10:
                            n = 0

                    # The first toolpath has finished computing so now display better
                    # information in the progress dialog.

                    # set the progress bar value to the number of completed toolpaths
                    progress.progressValue = generateToolpathFuture.numberOfCompleted

                    # set the progress bar max to the number of operations to be completed.
                    progress.maximumValue = generateToolpathFuture.numberOfOperations

                    # set the message for the progress dialog to track the progress value and the total number of operations to be completed.
                    progress.message = 'Generating %v of %m' + ' Toolpaths'
                    adsk.doEvents()
                progress.hide()

            parametersDumpFilename = os.path.join(camOutputFolder, "parameters.json")
            # it seems that the post processor always runs with the working directory being cam.temporaryFolder -- the outputFolder argument to cam.postProcess has no influence on
            # which folder fusion 360 uses as the working folder when running the post processor.  Therefore, we need to put the parameter dump file in cam.temporaryFolder 
            #never mind  -- I have modified the post processor so that it looks in the output folder (which it knows) for the parameters.json file.
            
            dump_user_params(doc.products.itemByProductType('DesignProductType'), parametersDumpFilename)
            setupsToBePosted = list(
                    filter(
                        lambda x: any(map(cam.checkToolpath,x.allOperations)),   
                        setupsToBePosted
                    )
                )
            #we have to wait until after we have performed g-code generation before culling any setups that have no valid operations because
            # sometimes an operation is considered an invalid even when a it would be valid after perrforming generation.
            for setup in setupsToBePosted:
                # create the postInput object
                postInput = adsk.cam.PostProcessInput.create(
                    # programName, 
                    setup.name,
                    
                    # postConfig, 
                    postConfig,
                    
                    # outputFolder, 
                    # cam.temporaryFolder,
                    camOutputFolder,
                    
                    # units,
                    # adsk.cam.PostOutputUnitOptions.DocumentUnitsOutput
                    adsk.cam.PostOutputUnitOptions.InchesOutput
                    # adsk.cam.PostOutputUnitOptions.MillimetersOutput
                )
                postInput.programComment = "" # we could potentially use the programComment as a (hacky) way to tell the post processor wher to find the parameters dump file, or to pass other information from fusion into the post processor (because the post processor can read the programComment.
                postInput.isOpenInEditor = False
                result = cam.postProcess(setup, postInput)
                # try:              
                    # result = cam.postProcess(setup, postInput)
                    # we put this 
                # except:
                    # #do nothing
                    # pass
            # ui.messageBox('command: {} executed successfully'.format(command.parentCommandDefinition.id))
        except:
            if ui:
                ui.messageBox('command executed failed: {}'.format(traceback.format_exc()))


class makeGcodeCommandCreatedEventHandler(adsk.core.CommandCreatedEventHandler):
    def __init__(self):
        super().__init__() 
    def notify(self, args):
        try:
            app = adsk.core.Application.get()
            ui = app.userInterface
            cmd = args.command
            # cmd.helpFile = 'help.html'
                                
            onExecute = makeGcodeCommandExecuteHandler()
            cmd.execute.add(onExecute)
            handlers.append(onExecute)

            # ui.messageBox('you have clicked the button for {}'.format(command.parentCommandDefinition.id))
        except:
            if ui:
                ui.messageBox('failed to create command: {}'.format(traceback.format_exc()))

#dumps all the user params from the specified design product to the file speicifed by filename, in json format.
def dump_user_params(design, filename):
    outputFile = open(filename, 'w', encoding="utf-8")
    dataToExport = {}
    for i in range(design.userParameters.count):
        param = design.userParameters.item(i)
        if param.unit in ["mm", "cm", "m", "micron", "in", "ft", "yd", "mi", 'nauticalMile', 'mil']: typeOfPhysicalQuantity = 'length'
        elif param.unit in ['rad', 'deg', 'grad']: typeOfPhysicalQuantity = 'angle'
        else: typeOfPhysicalQuantity = ''
        dataToExport[param.name] = {'value': param.value, 'typeOfPhysicalQuantity': typeOfPhysicalQuantity}
    outputFile.write(json.JSONEncoder().encode(dataToExport))
    outputFile.close()

def run(context):
    global commandId
    ui = None
    try:      
        app = adsk.core.Application.get()
        ui = app.userInterface
        
        # delete any existing command definition with the same id that might happen to exist already.
        existingCommandDefinition = ui.commandDefinitions.itemById(commandId)
        if existingCommandDefinition:
        	existingCommandDefinition.deleteMe()
        
        #createThe command definition
        commandDefinition = ui.commandDefinitions.addButtonDefinition(
            #id=
            commandId, 
            #name=
            "make gcode", 
            #tooltip=
            "invokes Neil's prefeerred post processor and posts all the toolpaths, marshalling the user parmaeters from this Fusion document along the way so that the post processing scripts can read the user parameters from the fusion document.",
            commandResources
        )
        onMakeGcodeCommandCreated = makeGcodeCommandCreatedEventHandler()
        commandDefinition.commandCreated.add(onMakeGcodeCommandCreated)
        handlers.append(onMakeGcodeCommandCreated) # keep the handler referenced beyond this function

        # delete any existing control with the same name in the destination toolbar that might happen to exist already
        existingToolbarControl = ui.toolbars.itemById(toolbarId).controls.itemById(commandId)
        if existingToolbarControl:
            existingToolbarControl.deleteMe()
        
        # insert the command into the toolbar
        global toolbarControl
        toolbarControl = ui.toolbars.itemById(toolbarId).controls.addCommand(commandDefinition)
        toolbarControl.isVisible = True

        # ui.messageBox("The command is added to " + toolbarId)
    except:
        if ui:
            ui.messageBox('Failed:\n{}'.format(traceback.format_exc()))

def stop(context):
    ui = None
    try:
        global commandDefinition
        if commandDefinition:
            commandDefinition.deleteMe()
            commandDefinition = None
        global toolbarControl
        if toolbarControl:
            toolbarControl.deleteMe()
            toolbarControl = None

    except:
        if ui:
            ui.messageBox('Failed:\n{}'.format(traceback.format_exc()))
