exp_dir = Dir.pwd + '/exp'
data_dir = Dir.pwd + '/data'

file "paper/tdpot.pdf" => [
  "paper/tdpot.tex",
  "paper/fig/perf_over_day.pdf",
  "paper/fig/ranks.pdf",
  "paper/fig/compression.pdf",
] do
  Dir.chdir "paper" do
    sh "latexmk -pdf tdpot.tex"
  end
end

task default: "paper/tdpot.pdf"

namespace "fig" do
  directory "paper/fig"

  file "paper/fig/perf_over_day.pdf" => FileList[
    "#{exp_dir}/1h/*.json",
    "#{exp_dir}/rand/*.json",
  ] + ["eval/perf_over_day.py", "paper/fig"] do
    sh "eval/perf_over_day.py"
  end

  file "paper/fig/ranks.pdf" => FileList[
    "#{exp_dir}/rank/*.json",
    "#{exp_dir}/rank_live/*.json",
  ] + ["eval/ranks.py", "paper/fig"] do
    sh "eval/ranks.py"
  end

  file "paper/fig/compression.pdf" => FileList[
    "#{exp_dir}/1h/*.json",
    "#{exp_dir}/rand/*.json",
    "#{exp_dir}/compression_1h/**/*.json",
    "#{exp_dir}/compression/**/*.json",
  ] + ["eval/compression.py", "paper/fig"] do
    sh "eval/compression.py"
  end

  file "paper/fig/parallelization.pdf" => FileList["#{exp_dir}/compression_par/*.json"] + ["eval/parallelization.py", "paper/fig"] do
    sh "eval/parallelization.py"
  end
end

namespace "table" do
  directory "paper/table"
end

osm_ger_src = 'https://download.geofabrik.de/europe/germany-200101.osm.pbf'
osm_ger_src_file = "#{data_dir}/germany-200101.osm.pbf"

osm_ger = "#{data_dir}/osm_ger/"
ptv_eur = "#{data_dir}/ptv20-eur-car/"

default = ['live_data', 28020000]
lite = ['lite_live_data', 37260000]
heavy = ['heavy_live_data', 56460000]

heavy_live_dir = "#{data_dir}/mapbox/live-speeds/2019-08-02-15:41/"
lite_live_dir = "#{data_dir}/mapbox/live-speeds/2019-07-16-10:21/"
typical_glob = "#{data_dir}/mapbox/typical-speeds/**/**/*.csv"
typical_file = "#{data_dir}/mapbox/typical-tuesday-cleaned.csv"
ptv_live_csv = "#{data_dir}/ptv/smallEuropeTuesdayCarWithIncidentDuration_ti.csv"

# SMALLER GRAPHS
# osm_ger_src = 'https://download.geofabrik.de/europe/germany/bremen-200101.osm.pbf'
# osm_ger_src_file = "#{data_dir}/bremen-200101.osm.pbf"
# ptv_eur = "#{data_dir}/ptv20-lux-car/"
# ptv_live_csv = "#{data_dir}/ptv/luxTuesdayCarWithIncidentDuration_ti.csv"

graphs = [[osm_ger, [heavy, lite]], [ptv_eur, [default]]]

namespace "prep" do
  directory ptv_eur

  file typical_file do
    Dir.chdir "code/rust_road_router" do
      sh "cat #{typical_glob} | cargo run --release --bin scrub_td_mapbox -- 576 864 > #{typical_file}"
    end
  end

  file osm_ger_src_file => data_dir do
    sh "wget -O #{osm_ger_src_file} #{osm_ger_src}"
  end

  directory osm_ger
  file osm_ger => ["code/osm_import/build/import_osm", osm_ger_src_file, typical_file] do
    wd = Dir.pwd
    Dir.chdir osm_ger do
      sh "#{wd}/code/osm_import/build/import_osm #{osm_ger_src_file} #{Dir[lite_live_dir + '*'].join(' ')} #{Dir[heavy_live_dir + '*'].join(' ')} #{typical_file}"
    end
     Dir.chdir "code/rust_road_router" do
       sh "cargo run --release --bin import_td_mapbox -- #{osm_ger} #{typical_file}"
     end
  end

  file "#{osm_ger}#{lite[0]}" => osm_ger do
    Dir.chdir "code/rust_road_router" do
      sh "cargo run --release --bin mapbox_to_live_array -- #{osm_ger} #{lite_live_dir} #{lite[0]}"
    end
  end
  file "#{osm_ger}#{heavy[0]}" => osm_ger do
    Dir.chdir "code/rust_road_router" do
      sh "cargo run --release --bin mapbox_to_live_array -- #{osm_ger} #{heavy_live_dir} #{heavy[0]}"
    end
  end
  file "#{ptv_eur}#{default[0]}" do
    Dir.chdir "code/rust_road_router" do
      sh "cargo run --release --bin ptv_ti_to_live -- #{ptv_eur} #{ptv_live_csv}"
    end
  end

  graphs.each do |graph, _|
    directory graph + "queries/1h"
    directory graph + "queries/rank"
    directory graph + "queries/uniform"

    file graph + "queries/1h" => graph do
      Dir.chdir "code/rust_road_router" do
        sh "cargo run --release --bin generate_1h_queries -- #{graph} 100000"
      end
    end

    file graph + "queries/rank" => graph do
      Dir.chdir "code/rust_road_router" do
        sh "cargo run --release --bin generate_rank_queries -- #{graph}"
      end
    end

    file graph + "queries/uniform" => graph do
      Dir.chdir "code/rust_road_router" do
        sh "cargo run --release --bin generate_rand_queries -- #{graph} 100000"
      end
    end

    file graph + "cch_perm" => [graph, "code/rust_road_router/lib/InertialFlowCutter/build/console"] do
      Dir.chdir "code/rust_road_router" do
        sh "./flow_cutter_cch_order.sh #{graph} #{Etc.nprocessors}"
      end
    end

    directory graph + "customized_corridor_mins"
    file graph + "customized_corridor_mins" => [graph + "cch_perm"] do
      Dir.chdir "code/rust_road_router" do
        sh "cargo run --release --bin interval_min_pre -- #{graph}"
      end
    end
  end
end

namespace "exp" do
  desc "Run all experiments"
  task queries: [:queries_pred, :queries_live, :compression]
  task all: [:queries, :customization, :preprocessing, :compression_par]

  directory "#{exp_dir}/rand"
  directory "#{exp_dir}/1h"
  directory "#{exp_dir}/rank"
  directory "#{exp_dir}/rand_live"
  directory "#{exp_dir}/1h_live"
  directory "#{exp_dir}/rank_live"
  directory "#{exp_dir}/compression"
  directory "#{exp_dir}/compression_1h"
  directory "#{exp_dir}/compression_times"
  directory "#{exp_dir}/compression_par"
  directory "#{exp_dir}/preprocessing"
  directory "#{exp_dir}/customization"

  task queries_pred: ["#{exp_dir}/rand", "#{exp_dir}/1h", "#{exp_dir}/rank"] + graphs.map { |g, _| g + "customized_corridor_mins" } + graphs.flat_map { |g, _| ['1h', 'uniform', 'rank'].map { |q| "#{g}queries/#{q}" } } do
    Dir.chdir "code/rust_road_router" do
      sh "cargo build --release --bin predicted_queries"
      sh "cargo build --release --bin predicted_queries_no_topo"
      graphs.each do |graph, _|
        sh "cargo run --release --bin interval_min_build -- #{graph}"
        sh "CHPOT_NUM_QUERIES=100000 numactl -N 1 -m 1 target/release/predicted_queries_no_topo #{graph} queries/uniform interval_min_pot > #{exp_dir}/rand/$(date --iso-8601=seconds).json"
        sh "CHPOT_NUM_QUERIES=100000 numactl -N 1 -m 1 target/release/predicted_queries #{graph} queries/uniform interval_min_pot > #{exp_dir}/rand/$(date --iso-8601=seconds).json"
        sh "CHPOT_NUM_QUERIES=100000 numactl -N 1 -m 1 target/release/predicted_queries #{graph} queries/1h interval_min_pot > #{exp_dir}/1h/$(date --iso-8601=seconds).json"
        sh "CHPOT_NUM_QUERIES=100000 numactl -N 1 -m 1 target/release/predicted_queries #{graph} queries/rank interval_min_pot > #{exp_dir}/rank/$(date --iso-8601=seconds).json"
        sh "rm -r #{graph}interval_min_pot"

        sh "cargo run --release --bin multi_metric_pre -- #{graph}"
        sh "CHPOT_NUM_QUERIES=100000 numactl -N 1 -m 1 target/release/predicted_queries_no_topo #{graph} queries/uniform multi_metric_pot > #{exp_dir}/rand/$(date --iso-8601=seconds).json"
        sh "CHPOT_NUM_QUERIES=100000 numactl -N 1 -m 1 target/release/predicted_queries #{graph} queries/uniform multi_metric_pot > #{exp_dir}/rand/$(date --iso-8601=seconds).json"
        sh "CHPOT_NUM_QUERIES=100000 numactl -N 1 -m 1 target/release/predicted_queries #{graph} queries/1h multi_metric_pot > #{exp_dir}/1h/$(date --iso-8601=seconds).json"
        sh "CHPOT_NUM_QUERIES=100000 numactl -N 1 -m 1 target/release/predicted_queries #{graph} queries/rank multi_metric_pot > #{exp_dir}/rank/$(date --iso-8601=seconds).json"
        sh "rm -r #{graph}multi_metric_pre"
        sh "rm -r #{graph}multi_metric_pot"

        sh "CHPOT_NUM_QUERIES=100000 numactl -N 1 -m 1 target/release/predicted_queries_no_topo #{graph} queries/uniform lower_bound_cch_pot > #{exp_dir}/rand/$(date --iso-8601=seconds).json"
        sh "CHPOT_NUM_QUERIES=100000 numactl -N 1 -m 1 target/release/predicted_queries #{graph} queries/uniform lower_bound_cch_pot > #{exp_dir}/rand/$(date --iso-8601=seconds).json"
        sh "CHPOT_NUM_QUERIES=100000 numactl -N 1 -m 1 target/release/predicted_queries #{graph} queries/1h lower_bound_cch_pot > #{exp_dir}/1h/$(date --iso-8601=seconds).json"
        sh "CHPOT_NUM_QUERIES=100000 numactl -N 1 -m 1 target/release/predicted_queries #{graph} queries/rank lower_bound_cch_pot > #{exp_dir}/rank/$(date --iso-8601=seconds).json"

        sh "CHPOT_NUM_QUERIES=1000 numactl -N 1 -m 1 target/release/predicted_queries_no_topo #{graph} queries/uniform zero > #{exp_dir}/rand/$(date --iso-8601=seconds).json"
        sh "CHPOT_NUM_QUERIES=1000 numactl -N 1 -m 1 target/release/predicted_queries #{graph} queries/uniform zero > #{exp_dir}/rand/$(date --iso-8601=seconds).json"
      end
    end
  end

  task queries_live: ["#{exp_dir}/rand_live", "#{exp_dir}/1h_live", "#{exp_dir}/rank_live"] + graphs.map { |g, _| g + "customized_corridor_mins" } + graphs.flat_map { |g, _| ['1h', 'uniform', 'rank'].map { |q| "#{g}queries/#{q}" } } + graphs.flat_map { |g, metrics| metrics.map { |m| g + m[0] } } do
    Dir.chdir "code/rust_road_router" do
      sh "cargo build --release --bin live_and_predicted_queries"
      sh "cargo build --release --bin live_and_predicted_queries_no_topo"
      graphs.each do |graph, metrics|
        metrics.each do |metric|
          sh "cargo run --release --bin interval_min_live_customization -- #{graph} #{metric[1]} #{metric[0]}"
          sh "CHPOT_NUM_QUERIES=100000 numactl -N 1 -m 1 target/release/live_and_predicted_queries_no_topo #{graph} #{metric[1]} #{metric[0]} queries/uniform interval_min_pot > #{exp_dir}/rand_live/$(date --iso-8601=seconds).json"
          sh "CHPOT_NUM_QUERIES=100000 numactl -N 1 -m 1 target/release/live_and_predicted_queries #{graph} #{metric[1]} #{metric[0]} queries/uniform interval_min_pot > #{exp_dir}/rand_live/$(date --iso-8601=seconds).json"
          sh "CHPOT_NUM_QUERIES=100000 numactl -N 1 -m 1 target/release/live_and_predicted_queries #{graph} #{metric[1]} #{metric[0]} queries/1h interval_min_pot > #{exp_dir}/1h_live/$(date --iso-8601=seconds).json"
          sh "CHPOT_NUM_QUERIES=100000 numactl -N 1 -m 1 target/release/live_and_predicted_queries #{graph} #{metric[1]} #{metric[0]} queries/rank interval_min_pot > #{exp_dir}/rank_live/$(date --iso-8601=seconds).json"
          sh "rm -r #{graph}interval_min_pot"

          sh "cargo run --release --bin multi_metric_pre -- #{graph}"
          sh "cargo run --release --bin multi_metric_live_customization -- #{graph} #{metric[1]} #{metric[0]}"
          sh "CHPOT_NUM_QUERIES=100000 numactl -N 1 -m 1 target/release/live_and_predicted_queries_no_topo #{graph} #{metric[1]} #{metric[0]} queries/uniform multi_metric_pot > #{exp_dir}/rand_live/$(date --iso-8601=seconds).json"
          sh "CHPOT_NUM_QUERIES=100000 numactl -N 1 -m 1 target/release/live_and_predicted_queries #{graph} #{metric[1]} #{metric[0]} queries/uniform multi_metric_pot > #{exp_dir}/rand_live/$(date --iso-8601=seconds).json"
          sh "CHPOT_NUM_QUERIES=100000 numactl -N 1 -m 1 target/release/live_and_predicted_queries #{graph} #{metric[1]} #{metric[0]} queries/1h multi_metric_pot > #{exp_dir}/1h_live/$(date --iso-8601=seconds).json"
          sh "CHPOT_NUM_QUERIES=100000 numactl -N 1 -m 1 target/release/live_and_predicted_queries #{graph} #{metric[1]} #{metric[0]} queries/rank multi_metric_pot > #{exp_dir}/rank_live/$(date --iso-8601=seconds).json"
          sh "rm -r #{graph}multi_metric_pre"
          sh "rm -r #{graph}multi_metric_pot"

          sh "CHPOT_NUM_QUERIES=100000 numactl -N 1 -m 1 target/release/live_and_predicted_queries_no_topo #{graph} #{metric[1]} #{metric[0]} queries/uniform lower_bound_cch_pot > #{exp_dir}/rand_live/$(date --iso-8601=seconds).json"
          sh "CHPOT_NUM_QUERIES=100000 numactl -N 1 -m 1 target/release/live_and_predicted_queries #{graph} #{metric[1]} #{metric[0]} queries/uniform lower_bound_cch_pot > #{exp_dir}/rand_live/$(date --iso-8601=seconds).json"
          sh "CHPOT_NUM_QUERIES=100000 numactl -N 1 -m 1 target/release/live_and_predicted_queries #{graph} #{metric[1]} #{metric[0]} queries/1h lower_bound_cch_pot > #{exp_dir}/1h_live/$(date --iso-8601=seconds).json"
          sh "CHPOT_NUM_QUERIES=100000 numactl -N 1 -m 1 target/release/live_and_predicted_queries #{graph} #{metric[1]} #{metric[0]} queries/rank lower_bound_cch_pot > #{exp_dir}/rank_live/$(date --iso-8601=seconds).json"

          sh "CHPOT_NUM_QUERIES=1000 numactl -N 1 -m 1 target/release/live_and_predicted_queries_no_topo #{graph} #{metric[1]} #{metric[0]} queries/uniform zero > #{exp_dir}/rand_live/$(date --iso-8601=seconds).json"
          sh "CHPOT_NUM_QUERIES=1000 numactl -N 1 -m 1 target/release/live_and_predicted_queries #{graph} #{metric[1]} #{metric[0]} queries/uniform zero > #{exp_dir}/rand_live/$(date --iso-8601=seconds).json"
        end
      end
    end
  end

  task compression: ["#{exp_dir}/compression", "#{exp_dir}/compression_1h", "#{exp_dir}/compression_times"] + graphs.map { |g, _| g + "customized_corridor_mins" } + graphs.flat_map { |g, _| ['1h', 'uniform'].map { |q| "#{g}queries/#{q}" } } do
    Dir.chdir "code/rust_road_router" do
      sh "cargo build --release --bin predicted_queries"
      graphs.each do |graph, _|
        ([2, 4, 8, 16, 32, 64] + [10, 20, 30, 40, 50, 60, 70, 80, 90]).each do |k|
          sh "mkdir #{exp_dir}/compression/#{k}" unless Dir.exist? "#{exp_dir}/compression/#{k}"
          sh "mkdir #{exp_dir}/compression_1h/#{k}" unless Dir.exist? "#{exp_dir}/compression_1h/#{k}"
          sh "mkdir #{exp_dir}/compression_times/#{k}" unless Dir.exist? "#{exp_dir}/compression_times/#{k}"

          sh "cargo run --release --bin interval_min_reduction -- #{graph} #{k} customized_corridor_mins reduced_corridor_mins > #{exp_dir}/compression_times/#{k}/$(date --iso-8601=seconds).json"
          sh "CHPOT_NUM_QUERIES=100000 numactl -N 1 -m 1 target/release/predicted_queries #{graph} queries/uniform interval_min_pot > #{exp_dir}/compression/#{k}/$(date --iso-8601=seconds).json"
          sh "CHPOT_NUM_QUERIES=100000 numactl -N 1 -m 1 target/release/predicted_queries #{graph} queries/1h interval_min_pot > #{exp_dir}/compression_1h/#{k}/$(date --iso-8601=seconds).json"
          sh "rm -r #{graph}interval_min_pot"
          sh "rm -r #{graph}reduced_corridor_mins"

          sh "cargo run --release --bin multi_metric_pre -- #{graph} multi_metric_pre multi_metric_pot #{k} > #{exp_dir}/compression_times/#{k}/$(date --iso-8601=seconds).json"
          sh "CHPOT_NUM_QUERIES=100000 numactl -N 1 -m 1 target/release/predicted_queries #{graph} queries/uniform multi_metric_pot > #{exp_dir}/compression/#{k}/$(date --iso-8601=seconds).json"
          sh "CHPOT_NUM_QUERIES=100000 numactl -N 1 -m 1 target/release/predicted_queries #{graph} queries/1h multi_metric_pot > #{exp_dir}/compression_1h/#{k}/$(date --iso-8601=seconds).json"
          sh "rm -r #{graph}multi_metric_pre"
          sh "rm -r #{graph}multi_metric_pot"
        end
      end
    end
  end

  task customization: ["#{exp_dir}/customization"] + graphs.map { |g, _| g + "customized_corridor_mins" } + graphs.flat_map { |g, metrics| metrics.map { |m| g + m[0] } } do
    Dir.chdir "code/rust_road_router" do
      graphs.each do |graph, metrics|
        metrics.each do |metric|
          sh "cargo run --release --bin multi_metric_pre -- #{graph}"
          100.times do
            sh "cargo run --release --bin multi_metric_live_customization -- #{graph} #{metric[1]} #{metric[0]} > #{exp_dir}/customization/$(date --iso-8601=seconds).json"
            sh "rm -r #{graph}multi_metric_pot"
            sh "cargo run --release --bin interval_min_live_customization -- #{graph} #{metric[1]} #{metric[0]} > #{exp_dir}/customization/$(date --iso-8601=seconds).json"
            sh "rm -r #{graph}interval_min_pot"
          end
        end
      end
    end
  end

  task preprocessing: ["#{exp_dir}/preprocessing", "code/rust_road_router/lib/InertialFlowCutter/build/console"] + graphs.map { |g, _| g } do
    graphs.each do |graph, _|
      10.times do
        Dir.chdir "code/rust_road_router" do
          filename = "#{exp_dir}/preprocessing/" + `date --iso-8601=seconds`.strip + '.out'
          sh "echo '#{graph}' >> #{filename}"
          sh "./flow_cutter_cch_order.sh #{graph} #{Etc.nprocessors} >> #{filename}"
          sh "cargo run --release --bin interval_min_pre -- #{graph} > #{exp_dir}/preprocessing/$(date --iso-8601=seconds).json"
          sh "rm -r #{graph}interval_min_pot"
          sh "cargo run --release --bin multi_metric_pre -- #{graph} > #{exp_dir}/preprocessing/$(date --iso-8601=seconds).json"
          sh "rm -r #{graph}multi_metric_pre"
          sh "rm -r #{graph}multi_metric_pot"
          sh "cargo run --release --bin cchpot_pre -- #{graph} > #{exp_dir}/preprocessing/$(date --iso-8601=seconds).json"
        end
      end
    end
  end

  task compression_par: ["#{exp_dir}/compression_par", ptv_eur] do
    Dir.chdir "code/rust_road_router" do
      10.times do
        [1, 2, 4, 8, 16].each do |k|
          sh "RAYON_NUM_THREADS=#{k} cargo run --release --bin interval_min_reduction -- #{ptv_eur} 16 customized_corridor_mins reduced_corridor_mins > #{exp_dir}/compression_par/$(date --iso-8601=seconds).json"
          sh "rm -r #{ptv_eur}interval_min_pot"
          sh "rm -r #{ptv_eur}reduced_corridor_mins"
        end
      end
    end
  end
end

namespace 'build' do
  task :osm_import => "code/osm_import/build/import_osm"

  directory "code/osm_import/build"

  file "code/osm_import/build/import_osm" => ["code/osm_import/build", "code/osm_import/src/bin/import_osm.cpp"] do
    Dir.chdir "code/osm_import/build/" do
      sh "cmake -DCMAKE_BUILD_TYPE=Release .. && make"
    end
  end

  task routingkit: "code/RoutingKit/bin"
  file "code/RoutingKit/bin" do
    Dir.chdir "code/RoutingKit/" do
      sh "./generate_make_file"
      sh "make"
    end
  end

  task :inertialflowcutter => "code/rust_road_router/lib/InertialFlowCutter/build/console"

  directory "code/rust_road_router/lib/InertialFlowCutter/build"
  desc "Building Flow Cutter Accelerated"
  file "code/rust_road_router/lib/InertialFlowCutter/build/console" => "code/rust_road_router/lib/InertialFlowCutter/build" do
    Dir.chdir "code/rust_road_router/lib/InertialFlowCutter/build" do
      sh "cmake -DCMAKE_BUILD_TYPE=Release .. && make console"
    end
  end
end

