import localUnitTest from './LocalUnit.test';
import nativeNoteEngineTest from './NativeNoteEngine.test';
import previewAdapterServiceTest from './PreviewAdapterService.test';
import settingsModelsTest from './SettingsModels.test';

export default function testsuite() {
  localUnitTest();
  nativeNoteEngineTest();
  previewAdapterServiceTest();
  settingsModelsTest();
}
