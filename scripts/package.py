import argparse, plistlib, pathlib, uuid

parser = argparse.ArgumentParser(description="Generate the Finder Quick Action metadata.")
parser.add_argument("output", type=pathlib.Path, help="Output .workflow directory")
args = parser.parse_args()
root=args.output / 'Contents'
app=root/'Resources/Install on Device.app/Contents'
app.mkdir(parents=True,exist_ok=True)
def write(path,obj):
    with open(path,'wb') as f: plistlib.dump(obj,f)
write(app/'Info.plist',dict(CFBundleIdentifier='local.artem.InstallOnDevice',CFBundleName='Install on Device',CFBundleExecutable='DeviceInstaller',CFBundlePackageType='APPL',CFBundleVersion='1',CFBundleShortVersionString='1.0',NSHighResolutionCapable=True,NSLocalNetworkUsageDescription='Find and install apps on your connected development devices.'))
script='''/usr/bin/open -n "$HOME/Library/Services/Install on Device.workflow/Contents/Resources/Install on Device.app" --args "$@"'''
action={'AMAccepts':{'Container':'List','Optional':True,'Types':['com.apple.cocoa.string']},'AMActionVersion':'2.0.3','AMApplication':['Automator'],'AMParameterProperties':{'COMMAND_STRING':{},'inputMethod':{},'shell':{},'source':{}},'AMProvides':{'Container':'List','Types':['com.apple.cocoa.string']},'ActionBundlePath':'/System/Library/Automator/Run Shell Script.action','ActionName':'Run Shell Script','ActionParameters':{'COMMAND_STRING':script,'CheckedForUserDefaultShell':True,'inputMethod':1,'shell':'/bin/zsh','source':''},'BundleIdentifier':'com.apple.RunShellScript','CFBundleVersion':'2.0.3','CanShowSelectedItemsWhenRun':False,'CanShowWhenRun':True,'Category':['AMCategoryUtilities'],'Class Name':'RunShellScriptAction','InputUUID':str(uuid.uuid4()),'OutputUUID':str(uuid.uuid4()),'UUID':str(uuid.uuid4()),'isViewVisible':True}
write(root/'document.wflow',{'AMApplicationBuild':'521','AMApplicationVersion':'2.10','AMDocumentVersion':'2','actions':[{'action':action,'isViewVisible':True}],'connectors':{},'workflowMetaData':{'applicationBundleID':'com.apple.finder','applicationBundleIDs':['com.apple.finder'],'applicationPath':'/System/Library/CoreServices/Finder.app','applicationPaths':['/System/Library/CoreServices/Finder.app'],'inputTypeIdentifier':'com.apple.Automator.fileSystemObject','outputTypeIdentifier':'com.apple.Automator.nothing','presentationMode':11,'processesInput':0,'serviceInputTypeIdentifier':'com.apple.Automator.fileSystemObject','serviceOutputTypeIdentifier':'com.apple.Automator.nothing','serviceProcessesInput':0,'systemImageName':'NSActionTemplate','useAutomaticInputType':False,'workflowTypeIdentifier':'com.apple.Automator.servicesMenu'}})
write(root/'Info.plist',{'CFBundleIdentifier':'local.artem.InstallOnDevice.QuickAction','CFBundleName':'Install on Device','NSServices':[{'NSMenuItem':{'default':'Install on Device'},'NSMessage':'runWorkflowAsService','NSRequiredContext':{'NSApplicationIdentifier':'com.apple.finder'},'NSSendFileTypes':['public.item'],'NSReturnTypes':[]}]})
