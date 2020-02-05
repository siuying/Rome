require 'fourflusher'

PLATFORMS = { 'iphonesimulator' => 'iOS',
              'appletvsimulator' => 'tvOS',
              'watchsimulator' => 'watchOS' }

def build_for_iosish_platform(sandbox, build_dir, target, device, simulator, configuration)
  deployment_target = target.platform_deployment_target
  target_label = target.cocoapods_target_label

  xcodebuild(sandbox, target_label, device, deployment_target, configuration)
  xcodebuild(sandbox, target_label, simulator, deployment_target, configuration)
  xcodebuild_catalyst(sandbox, target_label, configuration)

  spec_names = target.specs.map { |spec| [spec.root.name, spec.root.module_name] }.uniq
  spec_names.each do |root_name, module_name|
    xcframework_path = "#{build_dir}/#{module_name}.xcframework"
    device_framework_lib = "#{build_dir}/#{configuration}-#{device}/#{root_name}/#{module_name}.framework"
    simulator_framework_lib = "#{build_dir}/#{configuration}-#{simulator}/#{root_name}/#{module_name}.framework"
    catalyst_framework_lib = "#{build_dir}/#{configuration}-maccatalyst/#{root_name}/#{module_name}.framework"
    xcframework(xcframework_path, [device_framework_lib, simulator_framework_lib, catalyst_framework_lib])
    next unless File.directory?(device_framework_lib) && File.directory?(simulator_framework_lib) && File.directory?(catalyst_framework_lib)

    FileUtils.rmtree device_framework_lib if File.directory?(device_framework_lib)
    FileUtils.rmtree simulator_framework_lib if File.directory?(simulator_framework_lib)
    FileUtils.rmtree catalyst_framework_lib if File.directory?(catalyst_framework_lib)
  end
end

def xcodebuild(sandbox, target, sdk='macosx', deployment_target=nil, configuration)
  args = %W(-project #{sandbox.project_path.realdirpath} -scheme #{target} -configuration #{configuration} -sdk #{sdk})
  platform = PLATFORMS[sdk]
  args += Fourflusher::SimControl.new.destination(:oldest, platform, deployment_target) unless platform.nil?
  Pod::Executable.execute_command 'xcodebuild', args, true
end

def xcodebuild_catalyst(sandbox, target, destination='platform=macOS,variant=Mac Catalyst', configuration)
  args = %W(-project #{sandbox.project_path.realdirpath} -destination #{destination} -scheme #{target} -configuration #{configuration} ARCHS="x86_64")
  Pod::Executable.execute_command 'xcodebuild', args, true
end

def xcframework(output, framework_paths=[])
  args = %W(-create-xcframework -output #{output})
  framework_paths.each do |path|
    args += ["-framework", path]
  end
  Pod::Executable.execute_command 'xcodebuild', args, true
end

def enable_debug_information(project_path, configuration)
  project = Xcodeproj::Project.open(project_path)
  project.targets.each do |target|
    config = target.build_configurations.find { |config| config.name.eql? configuration }
    config.build_settings['DEBUG_INFORMATION_FORMAT'] = 'dwarf-with-dsym'
    config.build_settings['ONLY_ACTIVE_ARCH'] = 'NO'
  end
  project.save
end

def copy_dsym_files(dsym_destination, configuration)
  dsym_destination.rmtree if dsym_destination.directory?
  platforms = ['iphoneos', 'iphonesimulator', 'maccatalyst']
  platforms.each do |platform|
    dsym = Pathname.glob("build/#{configuration}-#{platform}/**/*.dSYM")
    dsym.each do |dsym|
      destination = dsym_destination + platform
      FileUtils.mkdir_p destination
      FileUtils.cp_r dsym, destination, :remove_destination => true
    end
  end
end

Pod::HooksManager.register('cocoapods-rome', :post_install) do |installer_context, user_options|
  enable_dsym = user_options.fetch('dsym', true)
  configuration = user_options.fetch('configuration', 'Debug')
  if user_options["pre_compile"]
    user_options["pre_compile"].call(installer_context)
  end

  sandbox_root = Pathname(installer_context.sandbox_root)
  sandbox = Pod::Sandbox.new(sandbox_root)

  enable_debug_information(sandbox.project_path, configuration) if enable_dsym

  build_dir = sandbox_root.parent + 'build'
  destination = sandbox_root.parent + 'Rome'

  Pod::UI.puts 'Building frameworks'

  build_dir.rmtree if build_dir.directory?
  targets = installer_context.umbrella_targets.select { |t| t.specs.any? }
  targets.each do |target|
    case target.platform_name
    when :ios then build_for_iosish_platform(sandbox, build_dir, target, 'iphoneos', 'iphonesimulator', configuration)
    when :osx then xcodebuild(sandbox, target.cocoapods_target_label, configuration)
    when :tvos then build_for_iosish_platform(sandbox, build_dir, target, 'appletvos', 'appletvsimulator', configuration)
    when :watchos then build_for_iosish_platform(sandbox, build_dir, target, 'watchos', 'watchsimulator', configuration)
    else raise "Unknown platform '#{target.platform_name}'" end
  end

  raise Pod::Informative, 'The build directory was not found in the expected location.' unless build_dir.directory?

  frameworks = []
  xcframeworks = Pathname.glob("build/*.xcframework")
  resources = []

  Pod::UI.puts "Built #{frameworks.count} #{'frameworks'.pluralize(frameworks.count)}"

  destination.rmtree if destination.directory?

  installer_context.umbrella_targets.each do |umbrella|
    umbrella.specs.each do |spec|
      consumer = spec.consumer(umbrella.platform_name)
      file_accessor = Pod::Sandbox::FileAccessor.new(sandbox.pod_dir(spec.root.name), consumer)
      frameworks += file_accessor.vendored_libraries
      frameworks += file_accessor.vendored_frameworks
      resources += file_accessor.resources
    end
  end
  frameworks.uniq!
  resources.uniq!

  Pod::UI.puts "Copying #{xcframeworks.count} #{'xcframeworks'.pluralize(xcframeworks.count)} " \
      "to `#{destination.relative_path_from Pathname.pwd}`"

  FileUtils.mkdir_p destination
  (frameworks + resources + xcframeworks).each do |file|
    FileUtils.cp_r file, destination, :remove_destination => true
  end

  copy_dsym_files(sandbox_root.parent + 'dSYM', configuration) if enable_dsym

  build_dir.rmtree if build_dir.directory?

  if user_options["post_compile"]
    user_options["post_compile"].call(installer_context)
  end
end
