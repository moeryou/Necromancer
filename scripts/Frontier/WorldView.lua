-- 唯一世界投影：精灵、占地、预览、命中和血条共用同一坐标源。
local C = require "Frontier.Config"
local View = {width=1568,height=882}
View.rowEdges={85,159,233,307,380,409,438,467,525,583,641,699,747}

function View.Point(x,y)
    local px=x<=23.5 and 25+(x-.5)*40 or 945+(x-23.5)*62.3
    local t=math.max(0,math.min(12,y-.5))
    local i=math.min(12,math.floor(t)+1)
    return px,View.rowEdges[i]+(t-i+1)*(View.rowEdges[i+1]-View.rowEdges[i])
end

function View.Cell(px,py)
    local col=px<945 and math.floor((px-25)/40)+1 or 24+math.floor((px-945)/62.3)
    for y=1,C.rows do
        if py>=View.rowEdges[y] and py<View.rowEdges[y+1] then return col,y end
    end
    return col,0
end

function View.Footprint(kind,x,y)
    local d=C.buildings[kind]
    local top=View.rowEdges[math.max(1,math.min(C.rows,y))]
    local bottom=View.rowEdges[math.max(1,math.min(C.rows+1,y+d.h))]
    return 25+(x-1)*40,top,d.w*40,bottom-top
end

-- 屋顶可适度突出，基座落在占地底边；开场与新建建筑不能另设绝对坐标。
function View.BuildingRect(kind,x,y,aspect)
    local px,py,pw,ph=View.Footprint(kind,x,y)
    local w=pw*1.5
    if kind=="warehouse" or kind=="block" then w=pw*1.1 end
    local h=w/aspect
    local bottom=py+ph-5
    return px+(pw-w)*.5,bottom-h,w,h,bottom
end
return View
