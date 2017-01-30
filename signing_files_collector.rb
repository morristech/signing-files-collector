require "fileutils"
require "logger"
require "open3"
require "set"

require "./codesigning_identities_collector.rb"
require "./collector_errors.rb"
require "./provisioning_profile_collector.rb"
require "./utils.rb"

load_or_install_gem("keychain")

$LOG_FILE_NAME = "signing_files_collector.log"

class SigningFilesCollector
  @@PACKAGE_NAME = "signing_files_package.zip"

  def initialize
    @execute_dir = Dir.pwd
    @log_file_path = File.join @execute_dir, $LOG_FILE_NAME
    @package_dir = generate_package_dir_name
    @provisioning_profiles = Array.new
    @codesigning_identities = Array.new
  end

  def collect
    begin
      $file_logger.info "Preparing to collect iOS signing files"
      create_temp_dir
      @provisioning_profiles = ProvisioningProfileCollector.new().collect
      @codesigning_identities = CodesigningIdentitiesCollector.new().collect
      discard_unreferenced
      create_upload_package
      add_log_to_upload_package
      #TODO upload package
      #TODO remove package dir
      #TODO remove log
      $stdout_logger.info "iOS signing file collection complete"
      $stdout_logger.indo "Please return to Greenhouse CI UI to continue"
      raise CollectorError

    rescue CollectorError
      puts "Signing file collection failed. Aborting"
      if File.exist?(@log_file_path)
        $stdout_logger.info "You can find the debug log at #{@log_file_path}"
        $stdout_logger.info "Please attach it when opening a support ticket"
      end
    ensure
      remove_package_dir
    end
  end

private

  def generate_package_dir_name
    timestamp = Time.now.to_i
    "/tmp/gh_signing_files_#{timestamp}"
  end

  def create_temp_dir
    $file_logger.debug "Creating temp directory #{@package_dir}"
    begin
      Dir.mkdir(@package_dir) if not File.exists?(@package_dir)
    rescue SystemCallError => ose
      $file_logger.error "Failed to prepare environment: #{ose.message}"
      raise CollectorError
    end
  end

  def discard_unreferenced
    $file_logger.info "Matching provisioning profiles & codesigning identities"
    #TODO Address Uku's comment about proper logging
    referenced_codesigning_ids = Set.new
    referenced_provisioning_profiles = Set.new
    @provisioning_profiles.each { |profile|
      @codesigning_identities.each { |csid|
        if profile.serials.include? csid.serial
          $file_logger.debug "Codesigning id #{csid} matches #{profile}"
          referenced_codesigning_ids.add csid
          referenced_provisioning_profiles.add profile
        end
      }
    }
    @provisioning_profiles = referenced_provisioning_profiles.to_a
    # @codesigning_identities.each { |csid|
    #   if not referenced_codesigning_ids.include? csid
    #     csid.remove
    #   end
    # }
    @codesigning_identities = referenced_codesigning_ids.to_a
  end

  def create_upload_package
    $file_logger.info "Preparing upload package"
    begin
      create_provisioning_profile_symlink
      Dir.chdir @package_dir
      signing_files = Dir.glob "*.mobileprovision"
      signing_files.concat Dir.glob("*.p12")
      $file_logger.debug "Packaging the following signing files:"
      $file_logger.debug signing_files

      if not signing_files.any?
        $file_logger.error "No siginig files found in the package dir, aborting"
        raise CollectorError
      end

      signing_files.each { |signing_file|
        #TODO add file by file to the zip file @@PACKAGE_NAME
      }

    rescue Exception => e
      $file_logger.error "Failed to prepare upload package: #{e.message}"
      raise CollectorError
    end
  end

  def create_provisioning_profile_symlink
    #TODO iterate provisioning profile list and call method create_symlink
  end

  def add_log_to_upload_package
    begin
      $file_logger.debug "Adding our log #{@log_file_path} to the upload package"
      Dir.chdir @package_dir
      #TODO Add log to zip with popen3

    rescue StandardError => err
      $file_logger.error "Failed to add log to upload package: #{err.message}"
      raise CollectorError
    end
  end

  def remove_package_dir
    $file_logger.info "Cleaning up"
    $file_logger.info "Removing package directory #{@package_dir}"
    begin
      FileUtils.rmtree @package_dir
      $file_logger.debug "Package dir removed successfully"
    rescue SystemCallError => ose
      $file_logger.error "Failed to clean up package dir: #{ose.message}"
      raise CollectorError
    end
  end

  def remove_log
    $file_logger.info "Removing log file #{@log_file_path}"
    begin
      File.delete @log_file_path
    rescue SystemCallError => ose
      $file_logger.error "Failed to clean up log file: #{ose.message}"
      raise CollectorError
    end
  end
end


File.delete($LOG_FILE_NAME) if File.exist?($LOG_FILE_NAME)

log_file = File.open $LOG_FILE_NAME, "a"
$file_logger = Logger.new log_file
$file_logger.level = Logger::DEBUG
$file_logger.formatter = proc { |severity, datetime, progname, msg|
  date_format = datetime.strftime("%Y-%m-%d %H:%M:%S")
  "#{date_format} #{severity} #{caller[4]} #{msg}\n"
}
$stdout_logger = Logger.new STDOUT
$stdout_logger.level = Logger::INFO

SigningFilesCollector.new().collect