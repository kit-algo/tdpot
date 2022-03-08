#include <routingkit/osm_profile.h>
#include <routingkit/osm_graph_builder.h>
#include <routingkit/osm_decoder.h>
#include <routingkit/vector_io.h>
#include <routingkit/id_mapper.h>
#include <routingkit/graph_util.h>
#include <routingkit/strongly_connected_component.h>
#include <routingkit/filter.h>

#include <functional>
#include <iostream>
#include <string>
#include <unordered_set>
#include <fstream>
#include <sstream>

using namespace RoutingKit;
using namespace std;

const uint8_t tunnel_bit = 1;
const uint8_t freeway_bit = 2;

int main(int argc, char*argv[]){
	if(argc < 2){
		cout << argv[0] << " pbf_file [traffic1.csv [traffic2.csv [...]]]\n\nWrites extracted files into current working directory"<<endl;
		return 2;
	}


        unordered_set<uint64_t>is_osm_node_traffic_end_point;

        for(int i=2; i<argc; ++i){
                std::ifstream in(argv[i]);
                if(!in){
                        cout << "Cannot open "<< argv[i]<<" skipping" << endl;
                }else{
                        string line;
                        while(getline(in, line)){
                                istringstream line_in(line);
                                string node_id;
                                getline(line_in, node_id, ',');
                                is_osm_node_traffic_end_point.insert(stol(node_id));
                                getline(line_in, node_id, ',');
                                is_osm_node_traffic_end_point.insert(stol(node_id));
                        }
                }
        }

        cout << "number of osm nodes that are traffic endpoints : "<< is_osm_node_traffic_end_point.size() << endl;

	string pbf_file = argv[1];

	std::function<void(const std::string&)>log_message = [](const string&msg){
		cout << msg << endl;
	};

	auto mapping = load_osm_id_mapping_from_pbf(
		pbf_file,
		[&](uint64_t osm_node_id, const TagMap&){
                        return is_osm_node_traffic_end_point.count(osm_node_id) > 0;
                },
		[&](uint64_t osm_way_id, const TagMap&tags){
			return is_osm_way_used_by_cars(osm_way_id, tags, log_message);
		},
		log_message
	);

	unsigned routing_way_count = mapping.is_routing_way.population_count();
	std::vector<uint32_t>way_speed(routing_way_count);

	auto routing_graph = load_osm_routing_graph_from_pbf(
		pbf_file,
		mapping,
		[&](uint64_t osm_way_id, unsigned routing_way_id, const TagMap&way_tags){
			way_speed[routing_way_id] = get_osm_way_speed(osm_way_id, way_tags, log_message);
			return get_osm_car_direction_category(osm_way_id, way_tags, log_message);
		},
		[&](uint64_t osm_relation_id, const std::vector<OSMRelationMember>&member_list, const TagMap&tags, std::function<void(OSMTurnRestriction)>on_new_restriction){
			return decode_osm_car_turn_restrictions(osm_relation_id, member_list, tags, on_new_restriction, log_message);
		},
		log_message,
                false,
                OSMRoadGeometry::uncompressed
	);

	unsigned arc_count  = routing_graph.arc_count();
	unsigned node_count  = routing_graph.node_count();

	std::vector<uint32_t>travel_time = routing_graph.geo_distance;
	for(unsigned a=0; a<arc_count; ++a){
		travel_time[a] *= 18000;
		travel_time[a] /= way_speed[routing_graph.way[a]];
		travel_time[a] /= 5;
	}

	std::vector<uint32_t>tail = invert_inverse_vector(routing_graph.first_out);

	cout << "total node count : " << node_count << endl;
	cout << "total arc count : " << arc_count << endl;

	IDMapper routing_node_mapper(mapping.is_routing_node);
	auto node_ids = std::vector<uint64_t>(routing_graph.first_out.size() - 1);
	for (unsigned i = 0; i < node_ids.size(); ++i) {
	  node_ids[i] = routing_node_mapper.to_global(i);
	}

        std::vector<unsigned>first_out = routing_graph.first_out;
        std::vector<unsigned>head = routing_graph.head;
        std::vector<unsigned>geo_distance = routing_graph.geo_distance;

        std::vector<float>latitude = routing_graph.latitude;
        std::vector<float>longitude = routing_graph.longitude;

        std::vector<bool>vec_node_in_largest_scc = compute_largest_strongly_connected_component(first_out, head);
        BitVector node_in_largest_scc(node_count);
        for(unsigned i=0; i<node_count; ++i){
                node_in_largest_scc.set(i, vec_node_in_largest_scc[i]);
        }

        BitVector arc_in_largest_scc(arc_count);
        for(unsigned i=0; i<arc_count; ++i){
                arc_in_largest_scc.set(i, node_in_largest_scc.is_set(tail[i]) && node_in_largest_scc.is_set(head[i]));
        }

        std::vector<unsigned>old_to_new_node(node_count);
        unsigned new_node_count = 0;
        for(unsigned x=0; x<node_count; ++x){
                if(node_in_largest_scc.is_set(x)){
                        old_to_new_node[x] = new_node_count++;
                }else{
                        old_to_new_node[x] = invalid_id;
                }
        }

        std::vector<unsigned>old_to_new_arc(arc_count);
        unsigned new_arc_count = 0;
        for(unsigned x=0; x<arc_count; ++x){
                if(arc_in_largest_scc.is_set(x)){
                        old_to_new_arc[x] = new_arc_count++;
                }else{
                        old_to_new_arc[x] = invalid_id;
                }
        }

	cout << "node count in largest scc: " << new_node_count << endl;
	cout << "arc count in largest scc: " << new_arc_count << endl;

        // first we get rid of the arcs outside of the lscc

        tail = keep_element_of_vector_if(arc_in_largest_scc, tail);
        head = keep_element_of_vector_if(arc_in_largest_scc, head);
        geo_distance = keep_element_of_vector_if(arc_in_largest_scc, geo_distance);
        travel_time = keep_element_of_vector_if(arc_in_largest_scc, travel_time);

        // next we get rid of the nodes outside of the lscc

        for(auto&x:tail){
                x = old_to_new_node[x];
                assert(x != invalid_id);
        }

        for(auto&x:head){
                x = old_to_new_node[x];
                assert(x != invalid_id);
        }

        {
                auto p = compute_inverse_sort_permutation_first_by_tail_then_by_head_and_apply_sort_to_tail(node_count, tail, head);
                head = apply_inverse_permutation(p, std::move(head));
                geo_distance = apply_inverse_permutation(p, std::move(geo_distance));
                travel_time = apply_inverse_permutation(p, std::move(travel_time));
        }

        arc_count = head.size();

        if(arc_count != 0)
        {
                unsigned out = 1;
                for(unsigned in = 1; in < arc_count; ++in){
                        if(tail[in-1] != tail[in] || head[in-1] != head[in]){
                                tail[out] = tail[in];
                                head[out] = head[in];
                                travel_time[out] = travel_time[in];
                                geo_distance[out] = geo_distance[in];
                                ++out;
                        }else{
                                if(travel_time[in] < travel_time[out-1]){
                                        travel_time[out-1] = travel_time[in];
                                }
                                if(geo_distance[in] < geo_distance[out-1]){
                                        geo_distance[out-1] = geo_distance[in];
                                }
                        }
                }
                arc_count = out;
        }

        tail.erase(tail.begin()+arc_count, tail.end());
        head.erase(head.begin()+arc_count, head.end());
        travel_time.erase(travel_time.begin()+arc_count, travel_time.end());
        geo_distance.erase(geo_distance.begin()+arc_count, geo_distance.end());

        first_out = invert_vector(tail, new_node_count);

        latitude = keep_element_of_vector_if(node_in_largest_scc, latitude);
        longitude = keep_element_of_vector_if(node_in_largest_scc, longitude);
        node_ids = keep_element_of_vector_if(node_in_largest_scc, node_ids);

	save_vector("first_out", first_out);
	save_vector("head", head);
	save_vector("tail", tail);
	save_vector("geo_distance", geo_distance);
	save_vector("travel_time", travel_time);
	save_vector("latitude", latitude);
	save_vector("longitude", longitude);
	save_vector("osm_node_ids", node_ids);
}
