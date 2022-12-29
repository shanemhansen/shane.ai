math.randomseed(os.time())
request = function()    
   url_path = "/product/" .. math.random(0,1000)
   return wrk.format("GET", url_path)
end
