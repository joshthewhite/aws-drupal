require 'zip'

# This is a simple example which uses rubyzip to
# recursively generate a zip file from the contents of
# a specified directory. The directory itself is not
# included in the archive, rather just its contents.
#
# Usage:
#   input_dir = "/tmp/input"
#   output_file = "/tmp/out.zip"
#   zf = ZipFileGenerator.new(input_dir, output_file)
#   zf.write
module DrupalAws
  module Tasks
    module Utils
      class ZipFileGenerator

        # Initialize with the directory to zip and the location of the output archive.
        def initialize(input_dir, output_file)
          @input_dir = input_dir
          @output_file = output_file
        end

        # Zip the input directory.
        def write(&block)
          entries = Dir.entries(@input_dir)
          entries.delete('.')
          entries.delete('..')

          io = Zip::File.open(@output_file, Zip::File::CREATE)

          write_entries(entries, '', io, &block)
          io.close
        end

        # A helper method to make the recursion work.
        private
        def write_entries(entries, path, io, &block)

          entries.each do |e|
            zip_file_path = (path == '') ? e : File.join(path, e)
            disk_file_path = File.join(@input_dir, zip_file_path)

            block.call(disk_file_path) unless block.nil?

            if File.directory?(disk_file_path)
              io.mkdir(zip_file_path)

              sub_directory = Dir.entries(disk_file_path)
              sub_directory.delete('.')
              sub_directory.delete('..')

              write_entries(sub_directory, zip_file_path, io, &block)
            else
              io.get_output_stream(zip_file_path) { |f| f.puts(File.open(disk_file_path, 'rb').read) }
            end
          end
        end

      end
    end
  end
end
