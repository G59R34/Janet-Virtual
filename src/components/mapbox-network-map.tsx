"use client";
import {useEffect,useRef} from "react";
import mapboxgl from "mapbox-gl";
import "mapbox-gl/dist/mapbox-gl.css";

type Station={id:string;code:string;label:string;latitude:number;longitude:number};
type Route={id:string;origin:[number,number];destination:[number,number]};
export function MapboxNetworkMap({token,stations,routes}:{token:string;stations:Station[];routes:Route[]}){
 const container=useRef<HTMLDivElement>(null);
 useEffect(()=>{if(!container.current||!token)return;const map=new mapboxgl.Map({container:container.current,accessToken:token,style:"mapbox://styles/mapbox/light-v11",center:[-116.4,36.1],zoom:5.5,attributionControl:true});map.addControl(new mapboxgl.NavigationControl({showCompass:true}),"top-right");map.on("load",()=>{map.addSource("jva-routes",{type:"geojson",data:{type:"FeatureCollection",features:routes.map(r=>({type:"Feature",properties:{id:r.id},geometry:{type:"LineString",coordinates:[r.origin,r.destination]}}))}});map.addLayer({id:"jva-routes",type:"line",source:"jva-routes",paint:{"line-color":"#8d9698","line-width":2,"line-dasharray":[3,2],"line-opacity":.8}});map.addSource("jva-airports",{type:"geojson",data:{type:"FeatureCollection",features:stations.map(s=>({type:"Feature",properties:{code:s.code,label:s.label},geometry:{type:"Point",coordinates:[s.longitude,s.latitude]}}))}});map.addLayer({id:"jva-airports",type:"circle",source:"jva-airports",paint:{"circle-radius":6,"circle-color":"#b5121b","circle-stroke-color":"#ffffff","circle-stroke-width":2}});map.addLayer({id:"jva-airport-labels",type:"symbol",source:"jva-airports",layout:{"text-field":["format",["get","code"],{"font-scale":1.05},"\n",{},["get","label"],{"font-scale":.75}],"text-font":["DIN Pro Medium","Arial Unicode MS Regular"],"text-size":11,"text-offset":[0,1.5],"text-anchor":"top","text-allow-overlap":false},paint:{"text-color":"#171a1c","text-halo-color":"#fff","text-halo-width":1.5}});if(stations.length){const bounds=new mapboxgl.LngLatBounds();stations.forEach(s=>bounds.extend([s.longitude,s.latitude]));map.fitBounds(bounds,{padding:70,maxZoom:9,duration:0})}});return()=>map.remove()},[token,stations,routes]);
 if(!token)return <div className="map-token-missing"><strong>Mapbox token required</strong><p>Add <code>NEXT_PUBLIC_MAPBOX_ACCESS_TOKEN</code> to <code>.env</code>, then restart the website.</p></div>;
 return <div ref={container} className="mapbox-network" aria-label="Geographic public network map"/>;
}
